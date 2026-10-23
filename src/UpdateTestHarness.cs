using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;

namespace Slotter
{
    // The staged proof uses the shipped code paths without a tray, UAC prompt or window.
    // Unsigned transactions and interruption hooks exist only in Debug builds.
    public static class UpdateTestHarness
    {
#if DEBUG
        public static void TransactionBoundary(string operation, string target)
        {
            if (Environment.GetEnvironmentVariable("SLOTTER_UPDATE_TEST_INTERRUPT") != operation) return;
            File.WriteAllText(Environment.GetEnvironmentVariable("SLOTTER_UPDATE_TEST_BOUNDARY_REPORT"), File.Exists(target) ? "target present" : "target missing");
            Environment.Exit(91);
        }
#endif
        public static bool Run(string[] args)
        {
            if (args.Length == 0 || (args[0] != "--update-test" && args[0] != "--update-test-relaunch")) return false;
            if (Environment.GetEnvironmentVariable("SLOTTER_UPDATE_TEST_MODE") != "1") throw new InvalidOperationException("The update test harness requires SLOTTER_UPDATE_TEST_MODE=1.");
            if (args[0] == "--update-test-relaunch")
            {
                if (Environment.GetEnvironmentVariable("SLOTTER_UPDATE_TEST_FAIL_START") == "1") return true;
                File.WriteAllText(args[1], UpdateInstaller.CurrentVersion);
                return true;
            }
            if (args.Length != 3) throw new ArgumentException("Expected --update-test unit|prepare|install report-path.");
            try
            {
                if (args[1] == "recovered-install")
                {
                    UpdateInstaller.ConfirmStartup(Array.Empty<string>());
                    args[1] = "install";
                }
                if (args[1] == "unit")
                {
                    int count = 0;
                    void Check(bool condition, string label) { if (!condition) throw new Exception(label); count++; }
                    string[] ordered = { "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.9", "1.0.0-alpha.10", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.0.1", "2.0.0" };
                    for (int i = 1; i < ordered.Length; i++) Check(SemanticVersion.Parse(ordered[i - 1]).CompareTo(SemanticVersion.Parse(ordered[i])) < 0, "SemVer order " + ordered[i]);
                    Check(SemanticVersion.Parse("1.0.0+one").CompareTo(SemanticVersion.Parse("1.0.0+two")) == 0, "Build metadata ignored");
                    Check(SemanticVersion.Parse("1.0.0--1").CompareTo(SemanticVersion.Parse("1.0.0-0")) > 0, "Hyphen prerelease is nonnumeric");
                    foreach (string bad in new[] { "1.0", "01.0.0", "1.0.0-alpha.01", "1.0.0-", "v1.0.0", "1.0.0+", "1.0.0\n" })
                    { bool rejected = false; try { SemanticVersion.Parse(bad); } catch (FormatException) { rejected = true; } Check(rejected, "Invalid SemVer " + bad); }
                    Check(SemanticVersion.Parse("999999999999999999999.0.0").CompareTo(SemanticVersion.Parse("2.0.0")) > 0, "Unbounded SemVer integer");
                    string item(string version, string os) => "<item><enclosure url='https://example.com/update.zip' sparkle:os='" + os + "' sparkle:shortVersionString='" + version + "' slotter:sha256='" + new string('a', 64) + "'/></item>";
                    string feed(string items) => "<rss xmlns:sparkle='" + UpdateFeed.SparkleNamespace + "' xmlns:slotter='" + UpdateFeed.SlotterNamespace + "'><channel>" + items + "</channel></rss>";
                    Check(UpdateFeed.Select(feed(item("9.0.0", "macos") + item("1.0.0-alpha.9", "windows") + item("1.0.0-alpha.10", "windows")), false).Version == "1.0.0-alpha.10", "Windows item and prerelease ordering");
                    Check(UpdateFeed.Select(feed(item("1.0.0", "macos")), false) == null, "Mac-only feed");
                    Check(UpdateFeed.Select(feed(item("1.0.0-alpha.99", "windows") + item("1.0.0", "windows")), false).Version == "1.0.0", "Stable precedes alpha");
                    bool badHash = false; try { UpdateFeed.Select(feed(item("1.0.0", "windows")).Replace(new string('a', 64), "bad"), false); } catch (InvalidDataException) { badHash = true; }
                    Check(badHash, "Missing hash refused");
                    foreach (string url in new[] { "http://example.com/feed.xml", "file:///C:/feed.xml", "https://user:pass@example.com/" })
                    { bool rejected = false; try { UpdateFeed.ValidateUrl(new Uri(url), true); } catch (InvalidDataException) { rejected = true; } Check(rejected, "Unsafe URL " + url); }
                    bool localRejected = false; try { UpdateFeed.ValidateUrl(new Uri("http://127.0.0.1/test"), false); } catch (InvalidDataException) { localRejected = true; }
                    Check(localRejected, "Loopback requires override"); UpdateFeed.ValidateUrl(new Uri("http://127.0.0.1/test"), true); count++;
                    File.WriteAllText(args[2], count + " updater checks passed");
                }
                else if (args[1] == "recover")
                {
                    UpdateInstaller.RecoverInterruptedTransaction(Environment.GetEnvironmentVariable("SLOTTER_UPDATE_TEST_RECOVERY_TARGET"));
                    File.WriteAllText(args[2], "recovery complete");
                }
                else if (args[1] == "cleanup")
                {
                    UpdateInstaller.ConfirmStartup(Array.Empty<string>());
                    File.WriteAllText(args[2], "startup cleanup " + UpdateInstaller.CurrentVersion);
                }
                else if (args[1] == "signer")
                {
                    UpdateInstaller.RequireSameSigner(Environment.GetEnvironmentVariable("SLOTTER_UPDATE_TEST_CURRENT_EXE"), Environment.GetEnvironmentVariable("SLOTTER_UPDATE_TEST_CANDIDATE_EXE"));
                    File.WriteAllText(args[2], "same valid signer");
                }
                else
                {
                    var feed = new Uri(Environment.GetEnvironmentVariable("SLOTTER_FEED_URL") ?? throw new Exception("Missing staged feed."));
                    string xml = Encoding.UTF8.GetString(Task.Run(() => UpdateInstaller.Fetch(feed, true, 2 * 1024 * 1024)).GetAwaiter().GetResult());
                    var release = UpdateFeed.Select(xml, true) ?? throw new Exception("No Windows update.");
                    string candidate = Task.Run(() => UpdateInstaller.Prepare(release, true)).GetAwaiter().GetResult();
                    File.WriteAllText(args[2], "verified " + release.Version + " candidate=" + candidate);
                    if (args[1] == "install") { UpdateInstaller.LaunchHelper(candidate, true); File.AppendAllText(args[2], " helper-ready"); }
                }
            }
            catch (Exception ex) { File.WriteAllText(args[2], "refused " + ex.Message); Environment.ExitCode = 1; }
            finally { File.WriteAllText(args[2] + ".complete", "complete"); }
            return true;
        }
    }
}
