using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
using Ykit;

namespace Snappy
{
    public partial class App : Application
    {
        public const string Version = "2.0";

        const int HWND_BROADCAST = 0xffff;
        const int CmdSettings = 1;
        const int HotkeyId = 0x51A;
        const uint HotkeyModifiers = 0x4003; // MOD_ALT | MOD_CONTROL | MOD_NOREPEAT
        const int VK_SPACE = 0x20;
        const int WM_HOTKEY = 0x0312;

        static uint commandMessage;
        Mutex instance;
        HwndSource messages;
        DeskTray tray;
        SnapEngine snapEngine;
        SettingsWindow settingsWindow;

        List<Profile> profiles = new List<Profile>();
        List<ProgItem> programsLib = new List<ProgItem>();
        string activeProfile = "";
        bool startWithWindows = true;
        bool hotkeyEnabled = true;
        bool hotkeyReady;
        int launching;

        public static System.Drawing.Icon TrayIcon;
        public static BitmapFrame WindowIcon;

        [DllImport("user32", CharSet = CharSet.Unicode)] static extern uint RegisterWindowMessage(string message);
        [DllImport("user32")] static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32")] static extern bool RegisterHotKey(IntPtr h, int id, uint modifiers, uint key);
        [DllImport("user32")] static extern bool UnregisterHotKey(IntPtr h, int id);

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            Ykit.DeskDisplayNames.SeedFromWallyOnce();
            string[] args = e.Args;

            commandMessage = RegisterWindowMessage("SnappyCommand");

            // Already running: hand a --settings request to it rather than starting a
            // second instance, otherwise just exit quietly.
            Mutex existing;
            if (Mutex.TryOpenExisting("SnappySingleInstance", out existing))
            {
                existing.Dispose();
                bool wantsSettings = args.Length > 0 && string.Equals(args[0], "--settings", StringComparison.OrdinalIgnoreCase);
                if (wantsSettings) PostMessage((IntPtr)HWND_BROADCAST, commandMessage, (IntPtr)CmdSettings, IntPtr.Zero);
                Shutdown();
                return;
            }

            // Snappy must run elevated to snap elevated windows (UIPI denies
            // SetWindowPos upward). Relaunch under UAC before anything else opens, so
            // the single-instance mutex below is the elevated instance.
            if (!Presence.IsElevated())
            {
                try
                {
                    Process.Start(new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName)
                    {
                        UseShellExecute = true,
                        Verb = "runas",
                        Arguments = string.Join(" ", args)
                    });
                    Shutdown();
                    return;
                }
                catch (System.ComponentModel.Win32Exception) { /* user cancelled UAC - continue unelevated */ }
            }

            bool createdNew;
            instance = new Mutex(true, "SnappySingleInstance", out createdNew);
            if (!createdNew) { instance.Dispose(); instance = null; Shutdown(); return; }

            DispatcherUnhandledException += delegate(object s, DispatcherUnhandledExceptionEventArgs ex)
            {
                Log.Write("ui error: " + ex.Exception);
                ex.Handled = true;
            };
            AppDomain.CurrentDomain.UnhandledException += delegate(object s, UnhandledExceptionEventArgs ex)
            {
                Log.Write("error: " + ex.ExceptionObject);
            };

            DeskTheme.Install(this);
            Log.Write("start " + Version + ": " + AppContext.BaseDirectory + ", elevated=" + Presence.IsElevated());
            LoadIcons();
            OpenMessageWindow();

            Config.EnsureDefault();
            LoadConfig();

            if (!Presence.IsElevated())
                Toast.Show("Snappy is running un-elevated", "Admin windows (Task Manager, Hyper-V, elevated terminals) will not snap until Snappy runs elevated.", false);

            Presence.ApplyStartupSetting(startWithWindows);
            ApplyHotkeySetting();

            snapEngine = new SnapEngine(delegate { return Config.FindProfile(profiles, activeProfile); });
            snapEngine.Start();
            SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;

            BuildTray();

            if (args.Length > 0 && string.Equals(args[0], "--settings", StringComparison.OrdinalIgnoreCase))
                Dispatcher.BeginInvoke(new Action(OpenSettings));
        }

        void LoadIcons()
        {
            try
            {
                Uri uri = new Uri("pack://application:,,,/Snappy.ico", UriKind.Absolute);
                WindowIcon = BitmapFrame.Create(uri);
                System.Windows.Resources.StreamResourceInfo info = GetResourceStream(uri);
                if (info != null) TrayIcon = new System.Drawing.Icon(info.Stream, 32, 32);
            }
            catch (Exception ex) { Log.Write("icons: " + ex.Message); }
        }

        // A top-level window, invisible and never shown. It has to be top-level rather
        // than message-only: HWND_BROADCAST does not reach message-only windows, and
        // that broadcast is how --settings reaches the running copy. The same window
        // holds the global hotkey.
        void OpenMessageWindow()
        {
            HwndSourceParameters p = new HwndSourceParameters("SnappyCommands");
            p.Width = 1;
            p.Height = 1;
            p.WindowStyle = 0;
            messages = new HwndSource(p);
            messages.AddHook(OnMessage);
        }

        IntPtr OnMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_HOTKEY && wParam.ToInt32() == HotkeyId)
            {
                handled = true;
                LaunchActiveProfile();
                return IntPtr.Zero;
            }
            if ((uint)msg == commandMessage)
            {
                handled = true;
                try { if (wParam.ToInt32() == CmdSettings) OpenSettings(); }
                catch (Exception ex) { Log.Write("command: " + ex.Message); }
                return IntPtr.Zero;
            }
            return IntPtr.Zero;
        }

        void ApplyHotkeySetting()
        {
            UnregisterHotKey(messages.Handle, HotkeyId);
            hotkeyReady = hotkeyEnabled && RegisterHotKey(messages.Handle, HotkeyId, HotkeyModifiers, VK_SPACE);
            if (hotkeyEnabled && !hotkeyReady) Log.Write("Ctrl+Alt+Space is already in use");
        }

        void LaunchActiveProfile()
        {
            Profile p = Config.FindProfile(profiles, activeProfile);
            if (p != null) ActivateProfile(p);
            else Toast.Show("No workspace selected", "Open Settings to create a workspace.", false);
        }

        void OnDisplaySettingsChanged(object sender, EventArgs e)
        {
            Dispatcher.BeginInvoke(new Action(delegate
            {
                if (snapEngine != null) snapEngine.CloseTargets();
                if (settingsWindow != null) settingsWindow.RefreshDisplays();
            }));
        }

        // ---------------------------------------------------------------- config

        void LoadConfig()
        {
            programsLib = Config.ReadPrograms();
            profiles = Config.ReadProfiles();
            activeProfile = Config.IniRead("Panel", "LastProfile", "");
            startWithWindows = Config.IniRead("Settings", "StartWithWindows", "1") != "0";
            hotkeyEnabled = Config.IniRead("Settings", "HotkeyEnabled", "1") != "0";
            if (Config.FindProfile(profiles, activeProfile) == null)
                activeProfile = profiles.Count > 0 ? profiles[0].Name : "";
        }

        // ------------------------------------------------------------------ tray

        void BuildTray()
        {
            tray = new DeskTray(TrayIcon, "Snappy — workspace launcher", messages.Handle);
            tray.Opening += delegate { RebuildMenu(); };
            tray.PrimaryAction = OpenSettings;
        }

        void RebuildMenu()
        {
            ItemCollection items = tray.Menu.Items;
            items.Clear();

            items.Add(DeskTray.Header("Snappy " + Version));
            items.Add(DeskTray.Rule());

            System.Windows.Forms.Screen[] screens = System.Windows.Forms.Screen.AllScreens;
            int visible = 0;
            foreach (Profile p in profiles)
            {
                if (!Config.ProfileVisible(p, screens)) continue;
                visible++;
                Profile captured = p;
                bool active = string.Equals(p.Name, activeProfile, StringComparison.OrdinalIgnoreCase);
                MenuItem item = DeskTray.Item(p.Name, Glyphs.Workspace, delegate { ActivateProfile(captured); });
                if (active) item.FontWeight = System.Windows.FontWeights.SemiBold;
                items.Add(item);
            }
            if (visible == 0)
            {
                MenuItem empty = DeskTray.Item("No workspaces yet", Glyphs.Workspace, null);
                empty.IsEnabled = false;
                items.Add(empty);
            }
            items.Add(DeskTray.Rule());

            items.Add(DeskTray.Item("Settings…", Glyphs.Settings, delegate { OpenSettings(); }));

            items.Add(DeskTray.Toggle("Start with Windows", Glyphs.Startup, startWithWindows, delegate
            {
                startWithWindows = !startWithWindows;
                Config.IniWrite("Settings", "StartWithWindows", startWithWindows ? "1" : "0");
                Presence.ApplyStartupSetting(startWithWindows);
            }));

            MenuItem hotkey = DeskTray.Toggle(hotkeyEnabled && !hotkeyReady ? "Global shortcut unavailable" : "Global launch shortcut", Glyphs.Hotkey, hotkeyEnabled, delegate
            {
                hotkeyEnabled = !hotkeyEnabled;
                Config.IniWrite("Settings", "HotkeyEnabled", hotkeyEnabled ? "1" : "0");
                ApplyHotkeySetting();
                Toast.Show(hotkeyReady ? "Shortcut ready" : hotkeyEnabled ? "Shortcut unavailable" : "Shortcut disabled",
                    hotkeyReady ? "Ctrl + Alt + Space launches the last workspace." : hotkeyEnabled ? "Another app is already using Ctrl + Alt + Space." : "You can re-enable it from this menu.",
                    hotkeyReady);
            });
            if (hotkeyEnabled && !hotkeyReady) hotkey.SetResourceReference(MenuItem.ForegroundProperty, "DangerBrush");
            items.Add(hotkey);

            MenuItem windows = DeskTray.Item("Window controls", Glyphs.Windows, null);
            windows.Items.Add(DeskTray.Item("Close every open app", Glyphs.Close, delegate
            {
                int count = LaunchEngine.CloseAllWindows();
                Toast.Show("Close requested", count == 1 ? "1 app was asked to close." : count + " apps were asked to close.", true);
            }));
            MenuItem force = DeskTray.Item("Force close every open app…", Glyphs.Kill, delegate
            {
                List<IntPtr> targets = SnapEngine.UserWindows();
                if (targets.Count == 0) { Toast.Show("Nothing to close", "No open app windows were found.", true); return; }
                if (!Confirm.Ask(null, "Force close every open app?", "This immediately ends " + targets.Count + " visible app windows. Unsaved work can be lost.", "Force close apps", true)) return;
                int count = LaunchEngine.ForceKillAll(targets);
                Toast.Show("Apps force closed", count == 1 ? "1 app process was ended." : count + " app processes were ended.", false);
            });
            force.SetResourceReference(MenuItem.ForegroundProperty, "DangerBrush");
            windows.Items.Add(force);
            items.Add(windows);

            items.Add(DeskTray.Rule());
            items.Add(DeskTray.Item("Exit Snappy", Glyphs.Exit, delegate { Quit(); }));
        }

        // ---------------------------------------------------------------- launch

        void ActivateProfile(Profile p)
        {
            if (Interlocked.CompareExchange(ref launching, 1, 0) != 0)
            {
                Toast.Show("A workspace is already launching", "Wait for the current apps to finish opening.", false);
                return;
            }
            activeProfile = p.Name;
            Config.IniWrite("Panel", "LastProfile", p.Name);
            List<ProgItem> lib = programsLib;
            int apps = 0;
            System.Windows.Forms.Screen[] screens = System.Windows.Forms.Screen.AllScreens;
            foreach (Zone zone in p.Zones) if (!string.IsNullOrEmpty(zone.Prog) && Config.ResolveScreenIndex(zone, screens) >= 0) apps++;
            if (apps == 0)
            {
                Interlocked.Exchange(ref launching, 0);
                if (p.Zones.Count == 0) Toast.Show(p.Name + " has no zones", "Open Settings and choose a layout preset.", false);
                else Toast.Show(p.Name + " is ready", p.Zones.Count == 1 ? "1 manual snap zone is active." : p.Zones.Count + " manual snap zones are active.", true);
                return;
            }
            Toast.Show("Launching " + p.Name, apps == 1 ? "Opening and placing 1 app…" : "Opening and placing " + apps + " apps…", true);
            Thread t = new Thread(delegate()
            {
                LaunchResult result = LaunchEngine.LaunchApps(p, lib);
                Interlocked.Exchange(ref launching, 0);
                try
                {
                    Dispatcher.BeginInvoke(new Action(delegate
                    {
                        if (result.Placed == result.Planned) Toast.Show(p.Name + " is ready", result.Placed == 1 ? "1 app snapped into place." : result.Placed + " apps snapped into place.", true);
                        else Toast.Show(p.Name + " launched with issues", result.Placed + " of " + result.Planned + " apps were placed. " + (result.FirstError ?? "Check snappy.log."), false);
                    }));
                }
                catch { }
            });
            t.IsBackground = true;
            t.Start();
        }

        // --------------------------------------------------------------- settings

        void OpenSettings()
        {
            if (settingsWindow != null)
            {
                settingsWindow.Activate();
                return;
            }
            settingsWindow = new SettingsWindow(profiles, activeProfile, programsLib, startWithWindows, hotkeyEnabled, hotkeyReady);
            settingsWindow.Saved += OnSettingsSaved;
            settingsWindow.Closed += delegate { settingsWindow = null; };
            settingsWindow.Show();
            settingsWindow.Activate();
        }

        void OnSettingsSaved(List<Profile> editedProfiles, List<ProgItem> editedLibrary, string editedActive, bool editedStartup, bool editedHotkey)
        {
            bool savedProfiles = Config.SaveProfiles(editedProfiles);
            bool savedPrograms = Config.WritePrograms(editedLibrary);
            bool savedSettings = Config.IniWrite("Settings", "StartWithWindows", editedStartup ? "1" : "0")
                & Config.IniWrite("Settings", "HotkeyEnabled", editedHotkey ? "1" : "0")
                & Config.IniWrite("Panel", "LastProfile", editedActive);
            if (savedProfiles && savedPrograms && savedSettings)
            {
                LoadConfig();
                Presence.ApplyStartupSetting(startWithWindows);
                ApplyHotkeySetting();
                Toast.Show("Settings saved", "Your workspaces are ready.", true);
            }
            else Toast.Show("Settings could not be saved", "Check that Snappy can write to its folder.", false);
        }

        // ------------------------------------------------------------------- exit

        void Quit()
        {
            try
            {
                SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
                if (snapEngine != null) snapEngine.Stop();
                UnregisterHotKey(messages.Handle, HotkeyId);
                if (tray != null) tray.Dispose();
                if (messages != null) messages.Dispose();
                if (instance != null) { instance.Dispose(); instance = null; }
            }
            catch (Exception ex) { Log.Write("quit: " + ex.Message); }
            Shutdown();
        }
    }
}
