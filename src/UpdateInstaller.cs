using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Threading;
using System.Threading.Tasks;

namespace Slotter
{
    public static class UpdateInstaller
    {
        public static string CurrentVersion => typeof(UpdateInstaller).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0] ?? "0.0.0";
        public static bool TestUnsigned
        {
            get
            {
#if DEBUG
                return Environment.GetEnvironmentVariable("SLOTTER_UPDATE_TEST_ALLOW_UNSIGNED") == "1";
#else
                return false;
#endif
            }
        }
        static string CanonicalExecutable(string path) => string.Equals(Path.GetFileName(path), "Slotter.exe.old", StringComparison.OrdinalIgnoreCase)
            ? path.Substring(0, path.Length - 4) : path;
        public static string Executable => CanonicalExecutable(Environment.ProcessPath);
        const long MaxDownload = 256L * 1024 * 1024;

        public static async Task<byte[]> Fetch(Uri url, bool localTest, long limit)
        {
            using var client = new HttpClient(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromMinutes(5) };
            for (int redirects = 0; redirects < 6; redirects++)
            {
                UpdateFeed.ValidateUrl(url, localTest);
                using var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
                if ((int)response.StatusCode >= 300 && (int)response.StatusCode < 400)
                {
                    if (response.Headers.Location == null) throw new IOException("Update redirect has no destination.");
                    url = new Uri(url, response.Headers.Location);
                    continue;
                }
                response.EnsureSuccessStatusCode();
                if (response.Content.Headers.ContentLength > limit) throw new IOException("Update download is too large.");
                using Stream input = await response.Content.ReadAsStreamAsync();
                using var output = new MemoryStream();
                byte[] buffer = new byte[65536];
                int read;
                while ((read = await input.ReadAsync(buffer)) > 0)
                {
                    if (output.Length + read > limit) throw new IOException("Update download is too large.");
                    await output.WriteAsync(buffer.AsMemory(0, read));
                }
                return output.ToArray();
            }
            throw new IOException("Too many update redirects.");
        }

        public static async Task<string> Prepare(UpdateRelease release, bool localTest, string currentExecutable = null)
        {
            currentExecutable ??= Executable;
            byte[] zip = await Fetch(release.Url, localTest, MaxDownload);
            if (!string.Equals(Convert.ToHexString(SHA256.HashData(zip)), release.Sha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("The downloaded update failed its SHA-256 checksum. Your current install has not changed.");
            using var archive = new ZipArchive(new MemoryStream(zip), ZipArchiveMode.Read);
            ZipArchiveEntry exe = null;
            foreach (var entry in archive.Entries)
                if (string.Equals(entry.FullName, "Slotter.exe", StringComparison.OrdinalIgnoreCase))
                { if (exe != null) throw new InvalidDataException("The update contains more than one Slotter.exe."); exe = entry; }
            if (exe == null || exe.Length > 512L * 1024 * 1024) throw new InvalidDataException("The update does not contain a valid Slotter.exe.");
            string stage = Path.Combine(Path.GetTempPath(), "Slotter-update-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(stage);
            string candidate = Path.Combine(stage, "Slotter.exe");
            try
            {
                await File.WriteAllBytesAsync(Path.Combine(stage, "update.zip"), zip);
                using (var input = exe.Open()) using (var output = File.Create(candidate))
                {
                    byte[] buffer = new byte[65536]; int read;
                    while ((read = await input.ReadAsync(buffer)) > 0)
                    {
                        if (output.Length + read > exe.Length) throw new InvalidDataException("The update executable exceeds its declared size.");
                        await output.WriteAsync(buffer.AsMemory(0, read));
                    }
                    if (output.Length != exe.Length) throw new InvalidDataException("The update executable is incomplete.");
                }
                RequireSameSigner(currentExecutable, candidate);
                string version = FileVersionInfo.GetVersionInfo(candidate).ProductVersion?.Split('+')[0];
                if (SemanticVersion.Parse(version).CompareTo(SemanticVersion.Parse(release.Version)) != 0)
                    throw new InvalidDataException("The update executable version does not match the feed.");
                return candidate;
            }
            catch { Directory.Delete(stage, true); throw; }
        }

        public static void RequireSameSigner(string current, string candidate)
        {
            if (TestUnsigned) return;
            string expected = ValidSigner(current);
            string actual = ValidSigner(candidate);
            if (!string.Equals(expected, actual, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("The update has a different signer from this Slotter install.");
        }

        static string ValidSigner(string path)
        {
            var file = new TrustFile { Size = (uint)Marshal.SizeOf<TrustFile>(), Path = path };
            IntPtr memory = Marshal.AllocHGlobal(Marshal.SizeOf<TrustFile>());
            Marshal.StructureToPtr(file, memory, false);
            var data = new TrustData { Size = (uint)Marshal.SizeOf<TrustData>(), UI = 2, Revocation = 1, Union = 1, File = memory, StateAction = 1, Flags = 0x80 };
            Guid action = new Guid("00AAC56B-CD44-11D0-8CC2-00C04FC295EE");
            try
            {
                int status = WinVerifyTrust(new IntPtr(-1), ref action, ref data);
                if (status != 0) throw new InvalidDataException("Authenticode verification failed for " + Path.GetFileName(path) + " (0x" + status.ToString("X8") + "). Unsigned development builds cannot update.");
                using var certificate = new X509Certificate2(X509Certificate.CreateFromSignedFile(path));
                return certificate.Thumbprint;
            }
            finally
            {
                data.StateAction = 2;
                WinVerifyTrust(new IntPtr(-1), ref action, ref data);
                Marshal.DestroyStructure<TrustFile>(memory);
                Marshal.FreeHGlobal(memory);
            }
        }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct TrustFile { public uint Size; [MarshalAs(UnmanagedType.LPWStr)] public string Path; public IntPtr File, Subject; }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct TrustData
        {
            public uint Size; public IntPtr Policy, Sip; public uint UI, Revocation, Union; public IntPtr File;
            public uint StateAction; public IntPtr State, Url; public uint Flags, Context; public IntPtr SignatureSettings;
        }
        [DllImport("wintrust.dll", ExactSpelling = true)] static extern int WinVerifyTrust(IntPtr window, ref Guid action, ref TrustData data);

        public static void LaunchHelper(string candidate, bool headless = false)
        {
            string helper = Path.Combine(Path.GetDirectoryName(candidate), "Slotter-updater.exe");
            File.Copy(Executable, helper, true);
            var start = new ProcessStartInfo(helper) { UseShellExecute = false, CreateNoWindow = true };
            foreach (string arg in new[] { "--apply-update", Environment.ProcessId.ToString(), Executable, candidate, headless ? "headless" : "normal" }) start.ArgumentList.Add(arg);
            using var helperProcess = Process.Start(start) ?? throw new IOException("The update helper could not start.");
            string ready = Path.Combine(Path.GetDirectoryName(candidate), "ready");
            var timer = Stopwatch.StartNew();
            while (!File.Exists(ready) && !helperProcess.HasExited && timer.Elapsed < TimeSpan.FromSeconds(20)) Thread.Sleep(50);
            if (!File.Exists(ready))
            {
                if (!helperProcess.HasExited) helperProcess.Kill();
                throw new IOException("The update helper could not prepare. Your current install has not changed.");
            }
        }

        public static bool RunHelper(string[] args)
        {
            if (args.Length == 0 || args[0] != "--apply-update") return false;
            string target = null, backup = null, incoming = null, ack = null;
            bool swapped = false;
            bool parentExited = false;
            try
            {
                if (args.Length != 5) throw new ArgumentException("Invalid update helper arguments.");
                target = Path.GetFullPath(args[2]);
                if (Path.GetFileName(target) != "Slotter.exe") throw new ArgumentException("Invalid update target.");
                RecoverInterruptedTransaction(target);
                string candidate = Path.GetFullPath(args[3]);
                RequireSameSigner(target, candidate);
                using (var parent = Process.GetProcessById(int.Parse(args[1])))
                {
                    if (!string.Equals(CanonicalExecutable(parent.MainModule.FileName), target, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("The update parent does not match its target.");
                    File.WriteAllText(Path.Combine(Path.GetDirectoryName(candidate), "ready"), "ready");
                    if (!parent.WaitForExit(30000)) throw new IOException("Slotter did not quit; update cancelled.");
                    parentExited = true;
                }
                backup = target + ".old";
                if (File.Exists(backup)) throw new IOException("A previous update backup still exists; restart Slotter before updating again.");
                incoming = target + ".update-" + Guid.NewGuid().ToString("N");
                File.Copy(candidate, incoming);
                using (var written = new FileStream(incoming, FileMode.Open, FileAccess.Write, FileShare.None)) written.Flush(true);
                RequireSameSigner(target, incoming);
                if (!SHA256.HashData(File.ReadAllBytes(candidate)).AsSpan().SequenceEqual(SHA256.HashData(File.ReadAllBytes(incoming)))) throw new IOException("The staged executable changed.");
                ack = Path.Combine(Path.GetDirectoryName(candidate), "started-" + Guid.NewGuid().ToString("N"));
                File.Replace(incoming, target, backup);
                swapped = true;
#if DEBUG
                UpdateTestHarness.TransactionBoundary("install", target);
#endif
                var start = new ProcessStartInfo(target) { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = Path.GetDirectoryName(target) };
                start.ArgumentList.Add(args[4] == "headless" ? "--update-test-relaunch" : "--updated");
                start.ArgumentList.Add(ack);
                using var launched = Process.Start(start) ?? throw new IOException("The updated Slotter could not start.");
                var timer = Stopwatch.StartNew();
                while (!File.Exists(ack) && !launched.HasExited && timer.Elapsed < TimeSpan.FromSeconds(30)) Thread.Sleep(100);
                if (!File.Exists(ack))
                {
                    if (!launched.HasExited) { launched.Kill(); launched.WaitForExit(10000); }
                    throw new IOException("The updated Slotter did not finish starting.");
                }
                // Startup acknowledgement commits the swap. Diagnostic I/O cannot undo a running update.
                swapped = false;
                try { File.Delete(backup); } catch { }
                try { File.WriteAllText(Path.Combine(Path.GetDirectoryName(candidate), "result.txt"), "updated " + File.ReadAllText(ack)); } catch { }
            }
            catch (Exception ex)
            {
                if (swapped)
                {
                    try
                    {
                        // Preserve the launch path while renaming the failed, possibly mapped image aside.
                        if (File.Exists(target)) File.Replace(backup, target, incoming);
                        else RecoverInterruptedTransaction(target);
#if DEBUG
                        UpdateTestHarness.TransactionBoundary("rollback", target);
#endif
                        ex = new IOException(ex.Message + " The previous version has been restored.", ex);
                    }
                    catch (Exception rollback) { ex = new IOException(ex.Message + " Rollback failed: " + rollback.Message, ex); }
                }
                try { if (target != null) RecoverInterruptedTransaction(target); }
                catch (Exception recovery) { ex = new IOException(ex.Message + " Recovery failed: " + recovery.Message, ex); }
                if (args.Length >= 4)
                {
                    try { File.WriteAllText(Path.Combine(Path.GetDirectoryName(args[3]), "result.txt"), "failed " + ex.Message); } catch { }
                }
                if (parentExited && File.Exists(target) && args[4] != "headless")
                {
                    var restart = new ProcessStartInfo(target) { UseShellExecute = false, CreateNoWindow = true };
                    restart.ArgumentList.Add("--update-failed"); restart.ArgumentList.Add(Path.Combine(Path.GetDirectoryName(args[3]), "result.txt"));
                    Process.Start(restart)?.Dispose();
                }
            }
            finally { try { if (incoming != null && File.Exists(incoming)) File.Delete(incoming); } catch { } }
            return true;
        }

        public static void RecoverInterruptedTransaction(string target)
        {
            if (File.Exists(target) || !File.Exists(target + ".old")) return;
            string restored = target + ".update-" + Guid.NewGuid().ToString("N");
            try
            {
                // A single-file .NET process can still load assemblies from its original bundle path.
                File.Copy(target + ".old", restored);
                using (var written = new FileStream(restored, FileMode.Open, FileAccess.Write, FileShare.None)) written.Flush(true);
                File.Move(restored, target);
            }
            finally { if (File.Exists(restored)) File.Delete(restored); }
        }

        public static bool RecoverStartup(string[] args)
        {
            string recoveryParent = Environment.GetEnvironmentVariable("SLOTTER_RECOVERY_PARENT");
            Environment.SetEnvironmentVariable("SLOTTER_RECOVERY_PARENT", null);
            if (recoveryParent != null)
            {
                Process parent;
                try { parent = Process.GetProcessById(int.Parse(recoveryParent)); }
                catch (ArgumentException) { parent = null; }
                if (parent != null)
                {
                    using (parent)
                    {
                        try
                        {
                            if (!parent.HasExited && !string.Equals(parent.MainModule.FileName, Executable + ".old", StringComparison.OrdinalIgnoreCase))
                                throw new IOException("The recovery parent does not match this Slotter backup.");
                        }
                        catch (InvalidOperationException) when (parent.HasExited) { }
                        catch (System.ComponentModel.Win32Exception) when (parent.HasExited) { }
                        if (!parent.WaitForExit(30000)) throw new IOException("The Slotter backup did not exit; recovery cannot continue.");
                    }
                }
            }
            RecoverInterruptedTransaction(Executable);
            if (string.Equals(Environment.ProcessPath, Executable, StringComparison.OrdinalIgnoreCase)) return false;
            var start = new ProcessStartInfo(Executable) { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = Path.GetDirectoryName(Executable) };
            start.Environment["SLOTTER_RECOVERY_PARENT"] = Environment.ProcessId.ToString();
            foreach (string arg in args) start.ArgumentList.Add(arg);
            Process.Start(start)?.Dispose();
            return true;
        }

        public static void ConfirmStartup(string[] args)
        {
            if (args.Length == 2 && (args[0] == "--updated" || args[0] == "--update-test-relaunch")) File.WriteAllText(args[1], CurrentVersion);
            if (args.Length == 0 || args[0] != "--updated")
            {
                try { if (File.Exists(Executable + ".old")) File.Delete(Executable + ".old"); } catch { }
                try
                {
                    string prefix = Path.GetFileName(Executable) + ".update-";
                    foreach (string failed in Directory.EnumerateFiles(Path.GetDirectoryName(Executable), prefix + "*"))
                        if (Guid.TryParseExact(Path.GetFileName(failed).Substring(prefix.Length), "N", out _))
                            try { File.Delete(failed); } catch { }
                }
                catch { }
            }
        }
    }
}
