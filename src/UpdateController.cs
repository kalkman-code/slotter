using System;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;

namespace Slotter
{
    public sealed class UpdateController : IDisposable
    {
        readonly Action quit;
        readonly DispatcherTimer timer = new DispatcherTimer { Interval = TimeSpan.FromDays(1) };
        bool busy;
        public bool Automatic => Config.IniRead("Settings", "AutomaticUpdateChecks", "1") != "0";
        public UpdateController(Action quit)
        {
            this.quit = quit;
            timer.Tick += async delegate { if (Automatic) await Check(false); };
            timer.Start();
            if (Automatic) Application.Current.Dispatcher.BeginInvoke(new Action(async () => await Check(false)), DispatcherPriority.ApplicationIdle);
        }
        public void SetAutomatic(bool enabled)
        {
            if (!Config.IniWrite("Settings", "AutomaticUpdateChecks", enabled ? "1" : "0"))
                Toast.Show("Update setting could not be saved", "Check that Slotter can write to its folder.", false);
        }
        public async Task Check(bool manual)
        {
            if (busy) return;
            busy = true;
            try
            {
                string configured = Environment.GetEnvironmentVariable("SLOTTER_FEED_URL");
                bool localTest = !string.IsNullOrWhiteSpace(configured);
                var feed = new Uri(localTest ? configured : UpdateFeed.ProductionUrl);
                var release = UpdateFeed.Select(Encoding.UTF8.GetString(await UpdateInstaller.Fetch(feed, localTest, 2 * 1024 * 1024)), localTest);
                if (release == null || SemanticVersion.Parse(release.Version).CompareTo(SemanticVersion.Parse(UpdateInstaller.CurrentVersion)) <= 0)
                {
                    if (manual) Toast.Show("Slotter is up to date", "You are running " + UpdateInstaller.CurrentVersion + ".", true);
                    return;
                }
                if (!manual && Config.IniRead("Settings", "SkippedUpdateVersion", "") == release.Version) return;
                int choice = UpdatePrompt.Ask(release.Version);
                if (choice == 2) Config.IniWrite("Settings", "SkippedUpdateVersion", release.Version);
                if (choice != 1) return;
                Toast.Show("Downloading Slotter " + release.Version, "Slotter will verify the update before restarting.", true);
                string candidate = await UpdateInstaller.Prepare(release, localTest);
                await Task.Run(() => UpdateInstaller.LaunchHelper(candidate));
                quit();
            }
            catch (Exception ex)
            {
                Log.Write("update: " + ex.Message);
                if (manual) Toast.Show("Update could not be completed", ex.Message, false);
                else Toast.Show("Update check failed", ex.Message, false);
            }
            finally { busy = false; }
        }
        public void Dispose() { timer.Stop(); }
    }

    public sealed class UpdatePrompt : Window
    {
        int choice;
        UpdatePrompt(string version)
        {
            Style = Ui.S("Win"); Title = "Slotter update"; Icon = App.WindowIcon;
            Width = 480; SizeToContent = SizeToContent.Height; ResizeMode = ResizeMode.NoResize;
            WindowStartupLocation = WindowStartupLocation.CenterScreen; ShowInTaskbar = false;
            SourceInitialized += delegate { Ui.TintTitleBar(this); };
            var body = new StackPanel { Margin = new Thickness(22, 20, 22, 20) };
            var heading = Ui.Text("Slotter " + version + " is available", 18, FontWeights.ExtraBold, "B.Ink");
            heading.TextWrapping = TextWrapping.Wrap; body.Children.Add(heading);
            var detail = Ui.Text("You are running " + UpdateInstaller.CurrentVersion + ". Install the update and restart Slotter when you are ready.", 13, FontWeights.Normal, "B.Ink2");
            detail.Margin = new Thickness(0, 6, 0, 0); detail.TextWrapping = TextWrapping.Wrap; body.Children.Add(detail);
            var actions = new StackPanel { Margin = new Thickness(0, 20, 0, 0) };
            var install = Ui.Button("Btn.Primary", "Install and restart", () => { choice = 1; Close(); }, "update-install");
            install.IsDefault = true; actions.Children.Add(install);
            var later = Ui.Button("Btn.Quiet", "Later", () => Close(), "update-later");
            later.IsCancel = true; later.Margin = new Thickness(0, 8, 0, 0); actions.Children.Add(later);
            actions.Children.Add(Ui.Button("Link", "Skip this version", () => { choice = 2; Close(); }, "update-skip"));
            body.Children.Add(actions); Content = body;
        }
        public static int Ask(string version) { var prompt = new UpdatePrompt(version); prompt.ShowDialog(); return prompt.choice; }
    }
}
