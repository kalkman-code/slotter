using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;

namespace Slotter
{
    public partial class App : Application
    {
        public static readonly string Version = typeof(App)
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "unknown";

        const int HWND_BROADCAST = 0xffff;
        const int CmdSettings = 1;
        const int HotkeyBaseId = 0x520;
        const uint ModNoRepeat = 0x4000;
        const int WM_HOTKEY = 0x0312;

        static uint commandMessage;
        Mutex instance;
        HwndSource messages;
        Tray tray;
        SnapEngine snapEngine;
        DesignerWindow settingsWindow;
        VirtualDesktops desktopWatcher;
        DesktopSnapshot desktopSnapshot;
        UpdateController updater;

        List<Profile> profiles = new List<Profile>();
        List<ProgItem> programsLib = new List<ProgItem>();
        string activeProfile = "";
        bool startWithWindows;
        bool hotkeyEnabled = true;
        bool hotkeyReady;
        bool snapShortcutsEnabled = true;
        bool followDesktop;
        bool recordingShortcut;
        bool configMigrationReady = true;
        Dictionary<SnapAction, KeyCombo> shortcuts = ShortcutTable.Defaults();
        readonly Dictionary<SnapAction, bool> shortcutReady = new Dictionary<SnapAction, bool>();
        Dictionary<string, string> desktopBindings = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        string manualProfile = "";
        Guid? lastKnownDesktopId;
        int launching;
        int launchGeneration;

        public static System.Drawing.Icon TrayIcon;
        public static BitmapFrame WindowIcon;

        [DllImport("user32", CharSet = CharSet.Unicode)] static extern uint RegisterWindowMessage(string message);
        [DllImport("user32")] static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32")] static extern bool RegisterHotKey(IntPtr h, int id, uint modifiers, uint key);
        [DllImport("user32")] static extern bool UnregisterHotKey(IntPtr h, int id);

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            string[] args = e.Args;
            if (UpdateInstaller.RecoverStartup(args)) { Shutdown(); return; }
            if (UpdateInstaller.RunHelper(args)) { Shutdown(); return; }
            if (UpdateTestHarness.Run(args)) { Shutdown(); return; }

            commandMessage = RegisterWindowMessage("SlotterCommand");

            // Already running: hand a --settings request to it rather than starting a
            // second instance, otherwise just exit quietly.
            Mutex existing;
            if (Mutex.TryOpenExisting("SlotterSingleInstance", out existing))
            {
                existing.Dispose();
                bool wantsSettings = args.Length > 0 && string.Equals(args[0], "--settings", StringComparison.OrdinalIgnoreCase);
                if (wantsSettings) PostMessage((IntPtr)HWND_BROADCAST, commandMessage, (IntPtr)CmdSettings, IntPtr.Zero);
                Shutdown();
                return;
            }

            // Slotter must run elevated to snap elevated windows (UIPI denies
            // SetWindowPos upward). Relaunch under UAC before anything else opens, so
            // the single-instance mutex below is the elevated instance.
            // Update helpers inherit the current token. Re-elevating here would end the
            // acknowledged process before its elevated replacement is ready, causing rollback.
            bool updateRelaunch = args.Length > 0 && (args[0] == "--updated" || args[0] == "--update-failed");
            if (!updateRelaunch && !Presence.IsElevated())
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
            instance = new Mutex(true, "SlotterSingleInstance", out createdNew);
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

            Ui.Install(Resources);
            Log.Write("start " + Version + ": " + AppContext.BaseDirectory + ", elevated=" + Presence.IsElevated());
            LoadIcons();
            OpenMessageWindow();

            Config.EnsureDefault();
            LoadConfig();
            manualProfile = activeProfile;
            Monitors.Remember();

            if (!Presence.IsElevated())
                Toast.Show("Slotter is running un-elevated", "Admin windows (Task Manager, Hyper-V, elevated terminals) will not snap until Slotter runs elevated.", false);

            Presence.RetireSnappy();
            Presence.ApplyStartupSetting(startWithWindows);
            ApplyHotkeySetting();

            snapEngine = new SnapEngine(delegate { return Config.ForDesktop(Config.FindProfile(profiles, activeProfile), desktopSnapshot == null || !desktopSnapshot.Available ? null : desktopSnapshot.CurrentId); });
            snapEngine.Start();
            desktopWatcher = new VirtualDesktops(Dispatcher);
            desktopWatcher.Changed += OnDesktopChanged;
            OnDesktopChanged(desktopWatcher.Current);
            SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;

            BuildTray();
            UpdateInstaller.ConfirmStartup(args);
            updater = new UpdateController(Quit);
            if (args.Length == 2 && args[0] == "--update-failed" && File.Exists(args[1]))
                Toast.Show("Update could not be completed", File.ReadAllText(args[1]), false);

            if (args.Length > 0 && string.Equals(args[0], "--settings", StringComparison.OrdinalIgnoreCase))
                Dispatcher.BeginInvoke(new Action(OpenSettings));
        }

        void LoadIcons()
        {
            try
            {
                Uri uri = new Uri("pack://application:,,,/Slotter.ico", UriKind.Absolute);
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
            HwndSourceParameters p = new HwndSourceParameters("SlotterCommands");
            p.Width = 1;
            p.Height = 1;
            p.WindowStyle = 0;
            messages = new HwndSource(p);
            messages.AddHook(OnMessage);
        }

        IntPtr OnMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_HOTKEY)
            {
                int id = wParam.ToInt32();
                int actionIndex = id - HotkeyBaseId;
                if (actionIndex >= 0 && actionIndex < ShortcutTable.All.Length)
                {
                    handled = true;
                    SnapAction action = ShortcutTable.All[actionIndex];
                    if (action == SnapAction.LaunchWorkspace) LaunchActiveProfile();
                    else KeySnap.Perform(action);
                    return IntPtr.Zero;
                }
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
            UnregisterShortcuts();
            shortcutReady.Clear();
            for (int i = 0; i < ShortcutTable.All.Length; i++)
            {
                SnapAction action = ShortcutTable.All[i];
                KeyCombo combo;
                bool enabled = action == SnapAction.LaunchWorkspace ? hotkeyEnabled : snapShortcutsEnabled;
                bool ready = false;
                if (!recordingShortcut && enabled && shortcuts.TryGetValue(action, out combo))
                {
                    uint modifiers = 0;
                    if ((combo.Modifiers & System.Windows.Input.ModifierKeys.Alt) != 0) modifiers |= 1;
                    if ((combo.Modifiers & System.Windows.Input.ModifierKeys.Control) != 0) modifiers |= 2;
                    if ((combo.Modifiers & System.Windows.Input.ModifierKeys.Shift) != 0) modifiers |= 4;
                    if ((combo.Modifiers & System.Windows.Input.ModifierKeys.Windows) != 0) modifiers |= 8;
                    int key = System.Windows.Input.KeyInterop.VirtualKeyFromKey(combo.Key);
                    ready = RegisterHotKey(messages.Handle, HotkeyBaseId + i, modifiers | ModNoRepeat, (uint)key);
                    if (!ready) Log.Write("shortcut unavailable: " + action + " " + combo.Format());
                }
                shortcutReady[action] = ready;
            }
            hotkeyReady = shortcutReady.ContainsKey(SnapAction.LaunchWorkspace) && shortcutReady[SnapAction.LaunchWorkspace];
            if (settingsWindow != null) settingsWindow.ShortcutStates(shortcutReady, hotkeyReady);
        }

        void UnregisterShortcuts()
        {
            if (messages == null) return;
            foreach (SnapAction action in ShortcutTable.All)
                UnregisterHotKey(messages.Handle, HotkeyBaseId + (int)action);
        }

        void SetShortcutRecording(bool recording)
        {
            recordingShortcut = recording;
            ApplyHotkeySetting();
        }

        void LaunchActiveProfile()
        {
            Profile p = Config.FindProfile(profiles, activeProfile);
            if (p != null) ActivateProfile(p);
            else Toast.Show("No workspace selected", "Open Settings to create a workspace.", false);
        }

        void OnDisplaySettingsChanged(object sender, EventArgs e)
        {
            Interlocked.Increment(ref launchGeneration);
            Dispatcher.BeginInvoke(new Action(delegate
            {
                if (snapEngine != null) snapEngine.CloseTargets();
                Monitors.Remember();
                if (settingsWindow != null) settingsWindow.RefreshDisplays();
            }));
        }

        void OnDesktopChanged(DesktopSnapshot snapshot)
        {
            Guid? previous = lastKnownDesktopId;
            if (previous != snapshot.CurrentId) Interlocked.Increment(ref launchGeneration);
            if (previous != snapshot.CurrentId && snapEngine != null) snapEngine.CloseTargets();
            desktopSnapshot = snapshot;
            bool changed = false;
            foreach (Profile profile in profiles) if (Config.ReconcileDesktops(profile, snapshot)) changed = true;
            if (changed) Config.SaveProfiles(profiles);
            ApplyDesktopProfile();
            if (snapshot.Available)
            {
                Guid id = snapshot.CurrentId.Value;
                if (previous.HasValue && previous.Value != id)
                {
                    int ordinal = snapshot.Desktops.FindIndex(d => d.Id == id) + 1;
                    string label = "Desktop " + (ordinal > 0 ? ordinal.ToString() : "?");
                    Profile selected = Config.FindProfile(profiles, activeProfile);
                    int plates = selected == null ? 0 : selected.VirtualPlates.Count(p => !p.Benched && string.Equals(p.DesktopId, id.ToString(), StringComparison.OrdinalIgnoreCase));
                    string state = plates + (plates == 1 ? " virtual plate" : " virtual plates");
                    Log.Write("desktop changed: " + label + " uuid=" + id + "; " + state);
                }
                lastKnownDesktopId = id;
            }
            if (settingsWindow != null) settingsWindow.DesktopState(snapshot);
        }

        void ApplyDesktopProfile()
        {
            string selected = manualProfile;
            if (Config.FindProfile(profiles, selected) == null && profiles.Count > 0) selected = profiles[0].Name;
            if (!string.Equals(activeProfile, selected, StringComparison.OrdinalIgnoreCase))
            {
                activeProfile = selected;
                if (snapEngine != null) snapEngine.CloseTargets();
                if (settingsWindow != null) settingsWindow.ActiveWorkspaceChanged(activeProfile);
            }
        }

        // ---------------------------------------------------------------- config

        void LoadConfig()
        {
            programsLib = Config.ReadPrograms();
            profiles = Config.ReadProfiles();
            desktopBindings = Config.ReadDesktopBindings();
            if (!Config.MigrateReservedProfiles(profiles, desktopBindings))
            {
                Log.Write("reserved workspace migration was incomplete");
                configMigrationReady = false;
                profiles = Config.ReadProfiles();
            }
            else
            {
                if (desktopBindings.Count > 0 || !string.IsNullOrEmpty(Config.IniRead("DesktopBindings", "List", "")))
                    Log.Write("discarded legacy desktop bindings; virtual plates now belong to workspaces");
                Config.WriteDesktopBindings(new Dictionary<string, string>());
            }
            bool reconciled = false;
            foreach (Profile profile in profiles) if (Config.ReconcileDesktops(profile, desktopSnapshot)) reconciled = true;
            if (reconciled) Config.SaveProfiles(profiles);
            activeProfile = Config.IniRead("Panel", "LastProfile", "");
            startWithWindows = Config.IniRead("Settings", "StartWithWindows", "0") == "1";
            hotkeyEnabled = Config.IniRead("Settings", "HotkeyEnabled", "1") != "0";
            snapShortcutsEnabled = Config.IniRead("Settings", "SnapShortcutsEnabled", "1") != "0";
            followDesktop = false;
            shortcuts = ShortcutTable.Read();
            if (Config.FindProfile(profiles, activeProfile) == null)
                activeProfile = profiles.Count > 0 ? profiles[0].Name : "";
            if (Config.FindProfile(profiles, manualProfile) == null) manualProfile = activeProfile;
        }

        // ------------------------------------------------------------------ tray

        void BuildTray()
        {
            tray = new Tray(TrayIcon, "Slotter", messages.Handle);
            tray.Opening += delegate { RebuildMenu(); };
            tray.PrimaryAction = OpenSettings;
        }

        void RebuildMenu()
        {
            ItemCollection items = tray.Menu.Items;
            items.Clear();

            items.Add(Tray.Header("Slotter " + Version));
            items.Add(Tray.Rule());
            items.Add(Tray.Caption("Launch a workspace"));

            System.Windows.Forms.Screen[] screens = System.Windows.Forms.Screen.AllScreens;
            foreach (Profile p in profiles)
            {
                Profile captured = p;
                // A workspace whose monitor is away stays listed, greyed, with the reason in words.
                if (!Config.ProfileVisible(p, screens))
                {
                    List<string> away = new List<string>();
                    foreach (Zone z in p.Zones)
                        if (Config.ResolveScreenIndex(z, screens) < 0)
                        {
                            string label = Config.MonitorLabel(z.MonKey);
                            if (!away.Contains(label)) away.Add(label);
                        }
                    MenuItem off = Tray.Item(p.Name, string.Join(" + ", away.ToArray()) + " offline", null);
                    off.IsEnabled = false;
                    items.Add(off);
                    continue;
                }
                int apps = 0;
                Profile plan = Config.ForDesktop(p, desktopSnapshot == null || !desktopSnapshot.Available ? null : desktopSnapshot.CurrentId);
                foreach (Zone z in plan.Zones) if (!string.IsNullOrEmpty(z.Prog)) apps++;
                MenuItem item = Tray.Item(p.Name, apps == 0 ? "No apps" : apps == 1 ? "1 app" : apps + " apps", delegate { ActivateProfile(captured); });
                if (string.Equals(p.Name, activeProfile, StringComparison.OrdinalIgnoreCase)) item.FontWeight = System.Windows.FontWeights.SemiBold;
                items.Add(item);
            }
            if (profiles.Count == 0)
            {
                MenuItem empty = Tray.Item("No workspaces yet", null, null);
                empty.IsEnabled = false;
                items.Add(empty);
            }
            items.Add(Tray.Rule());

            items.Add(Tray.Item("Settings…", null, delegate { OpenSettings(); }));
            items.Add(Tray.Item("Check for updates…", null, async delegate { await updater.Check(true); }));

            items.Add(Tray.Toggle("Start with Windows", startWithWindows, delegate
            {
                startWithWindows = !startWithWindows;
                Config.IniWrite("Settings", "StartWithWindows", startWithWindows ? "1" : "0");
                Presence.ApplyStartupSetting(startWithWindows);
            }));

            MenuItem hotkey = Tray.Toggle(hotkeyEnabled && !hotkeyReady ? "Global launch shortcut unavailable" : "Global launch shortcut", hotkeyEnabled, delegate
            {
                hotkeyEnabled = !hotkeyEnabled;
                Config.IniWrite("Settings", "HotkeyEnabled", hotkeyEnabled ? "1" : "0");
                ApplyHotkeySetting();
                if (settingsWindow != null) settingsWindow.ShortcutStates(shortcutReady, hotkeyReady);
                KeyCombo launchCombo;
                string launchText = shortcuts.TryGetValue(SnapAction.LaunchWorkspace, out launchCombo)
                    ? launchCombo.Format() + " launches the last workspace."
                    : "The launch shortcut is unbound.";
                string launchError = shortcuts.ContainsKey(SnapAction.LaunchWorkspace)
                    ? "Another app holds its shortcut." : "No launch shortcut is assigned.";
                Toast.Show(hotkeyReady ? "Shortcut ready" : hotkeyEnabled ? "Shortcut unavailable" : "Shortcut off",
                    hotkeyReady ? launchText : hotkeyEnabled ? null : "You can turn it on again from this menu.",
                    hotkeyReady, hotkeyEnabled && !hotkeyReady ? launchError : null);
            });
            if (hotkeyEnabled && !hotkeyReady) hotkey.Foreground = Ui.B("B.Error");
            items.Add(hotkey);

            MenuItem windows = Tray.Item("Window controls", null, null);
            windows.Items.Add(Tray.Item("Close every open app", null, delegate
            {
                int count = LaunchEngine.CloseAllWindows();
                Toast.Show("Close requested", count == 1 ? "1 app was asked to close." : count + " apps were asked to close.", true);
            }));
            windows.Items.Add(Tray.Item("Force close every open app…", null, delegate
            {
                List<IntPtr> targets = SnapEngine.UserWindows();
                if (targets.Count == 0) { Toast.Show("Nothing to close", "No open app windows were found.", true); return; }
                if (!Confirm.Ask(null, "Force close every open app?", "This immediately ends " + targets.Count + " visible app windows. Unsaved work can be lost.", "Force close apps", true)) return;
                int count = LaunchEngine.ForceKillAll(targets);
                Toast.Show("Apps force closed", count == 1 ? "1 app process was ended." : count + " app processes were ended.", false);
            }));
            items.Add(windows);

            items.Add(Tray.Rule());
            items.Add(Tray.Item("Exit Slotter", null, delegate { Quit(); }));
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
            int generation = Interlocked.Increment(ref launchGeneration);
            manualProfile = p.Name;
            Config.IniWrite("Panel", "LastProfile", p.Name);
            List<ProgItem> lib = programsLib;
            Profile plan = Config.ForDesktop(p, desktopSnapshot == null || !desktopSnapshot.Available ? null : desktopSnapshot.CurrentId);
            int apps = 0;
            System.Windows.Forms.Screen[] screens = System.Windows.Forms.Screen.AllScreens;
            foreach (Zone zone in plan.Zones) if (!string.IsNullOrEmpty(zone.Prog) && Config.ResolveScreenIndex(zone, screens) >= 0) apps++;
            if (apps == 0)
            {
                Interlocked.Exchange(ref launching, 0);
                if (plan.Zones.Count == 0) Toast.Show(p.Name + " has no zones", "Open Settings and choose a layout preset.", false);
                else Toast.Show(p.Name + " is ready", plan.Zones.Count == 1 ? "1 manual snap zone is active." : plan.Zones.Count + " manual snap zones are active.", true);
                return;
            }
            Toast.Show("Launching " + p.Name, apps == 1 ? "Opening and placing 1 app…" : "Opening and placing " + apps + " apps…", true);
            Thread t = new Thread(delegate()
            {
                LaunchResult result = LaunchEngine.LaunchApps(plan, lib, delegate { return Volatile.Read(ref launchGeneration) == generation; });
                Interlocked.Exchange(ref launching, 0);
                try
                {
                    Dispatcher.BeginInvoke(new Action(delegate
                    {
                        if (result.Cancelled)
                        {
                            Toast.Show("Launch stopped", "The desktop or display changed. Launch the workspace again on this desktop.", false);
                            return;
                        }
                        string placed = result.Placed + " of " + result.Planned + (result.Planned == 1 ? " app placed." : " apps placed.");
                        if (result.Placed == result.Planned) Toast.Show(p.Name + " launched.", placed, true);
                        else Toast.Show(p.Name + " launched.", placed, false, result.FirstError ?? "Check slotter.log.");
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
            settingsWindow = new DesignerWindow(profiles, activeProfile, programsLib, startWithWindows, hotkeyEnabled, hotkeyReady,
                shortcuts, snapShortcutsEnabled, shortcutReady, followDesktop, desktopSnapshot, desktopBindings);
            settingsWindow.Saved += OnSettingsSaved;
            settingsWindow.CheckUpdates += async delegate { await updater.Check(true); };
            settingsWindow.AutomaticUpdatesChanged += updater.SetAutomatic;
            settingsWindow.RecordingChanged += SetShortcutRecording;
            settingsWindow.WorkspaceSet += delegate (string name)
            {
                Profile workspace = Config.FindProfile(profiles, name);
                if (workspace != null) ActivateProfile(workspace);
            };
            settingsWindow.Closed += delegate { settingsWindow = null; };
            settingsWindow.Show();
            settingsWindow.Activate();
        }

        bool OnSettingsSaved(List<Profile> editedProfiles, List<ProgItem> editedLibrary, string editedActive, bool editedStartup, bool editedHotkey,
            Dictionary<SnapAction, KeyCombo> editedShortcuts, bool editedSnapShortcuts, bool editedFollowDesktop,
            Dictionary<string, string> editedBindings, Dictionary<string, string> profileRenames)
        {
            if (!configMigrationReady)
            {
                Toast.Show("Settings could not be saved", "Reserved workspace migration must complete before Slotter can update profiles.ini.", false);
                return false;
            }
            string renamedManual;
            string retainedManual = profileRenames.TryGetValue(manualProfile, out renamedManual) ? renamedManual : manualProfile;
            if (Config.FindProfile(editedProfiles, editedActive) != null) retainedManual = editedActive;
            else if (Config.FindProfile(editedProfiles, retainedManual) == null) retainedManual = editedActive;
            bool savedProfiles = Config.SaveProfiles(editedProfiles);
            bool savedPrograms = Config.WritePrograms(editedLibrary);
            bool savedSettings = Config.IniWrite("Settings", "StartWithWindows", editedStartup ? "1" : "0")
                & Config.IniWrite("Settings", "HotkeyEnabled", editedHotkey ? "1" : "0")
                & Config.IniWrite("Settings", "SnapShortcutsEnabled", editedSnapShortcuts ? "1" : "0")
                & Config.IniWrite("Settings", "FollowDesktop", editedFollowDesktop ? "1" : "0")
                & Config.IniWrite("Panel", "LastProfile", retainedManual);
            bool savedOther = Config.WriteShortcuts(editedShortcuts);
            if (savedProfiles && savedPrograms && savedSettings && savedOther)
            {
                manualProfile = retainedManual;
                LoadConfig();
                Presence.ApplyStartupSetting(startWithWindows);
                ApplyHotkeySetting();
                ApplyDesktopProfile();
                if (settingsWindow != null) settingsWindow.ShortcutStates(shortcutReady, hotkeyReady);
                return true;
            }
            Toast.Show("Settings could not be saved", "Check that Slotter can write to its folder.", false);
            return false;
        }

        // ------------------------------------------------------------------- exit

        void Quit()
        {
            try
            {
                SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
                if (snapEngine != null) snapEngine.Stop();
                UnregisterShortcuts();
                if (desktopWatcher != null) desktopWatcher.Dispose();
                if (tray != null) tray.Dispose();
                if (updater != null) updater.Dispose();
                if (messages != null) messages.Dispose();
                if (instance != null) { instance.Dispose(); instance = null; }
            }
            catch (Exception ex) { Log.Write("quit: " + ex.Message); }
            Shutdown();
        }
    }
}
