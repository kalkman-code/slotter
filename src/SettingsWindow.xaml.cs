using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

namespace Snappy
{
    // A non-selectable group label in the workspace list ("RDP", "Ultrawide", ...).
    public class WorkspaceHeader
    {
        public string Label { get; set; }
        // WPF falls back to ToString() for a ListBoxItem's accessible name when the
        // container itself carries no explicit AutomationProperties.Name (setting it
        // on the DataTemplate's content sets that element's name, not the item's).
        public override string ToString() { return Label; }
    }

    // The Workspace Designer: workspace list, the monitor/zone canvas, and the
    // inspector for whatever is selected. All Save does is hand the edited state back
    // to App via the Saved event -- App owns writing profiles.ini.
    public partial class SettingsWindow : Ykit.DeskWindow
    {
        public event Action<List<Profile>, List<ProgItem>, string, bool, bool> Saved;

        readonly List<Profile> result;
        readonly List<ProgItem> library;
        string activeProfileName;
        readonly bool hotkeyAvailable;
        readonly List<object> shown = new List<object>();
        bool sync;
        bool dirty;
        bool closingApproved;

        static readonly string[] PresetNames = {
            "Full", "2 columns", "3 columns", "4 columns", "2 rows", "3 rows", "2x2 grid",
            "Left half", "Right half", "Left third", "Centre third", "Right third",
            "Left two-thirds + right third", "Left third + right two-thirds" };

        static readonly double[][][] PresetSets = {
            new[]{ new double[]{0,0,100,100} },
            new[]{ new double[]{0,0,50,100}, new double[]{50,0,50,100} },
            new[]{ new double[]{0,0,33.33,100}, new double[]{33.33,0,33.34,100}, new double[]{66.67,0,33.33,100} },
            new[]{ new double[]{0,0,25,100}, new double[]{25,0,25,100}, new double[]{50,0,25,100}, new double[]{75,0,25,100} },
            new[]{ new double[]{0,0,100,50}, new double[]{0,50,100,50} },
            new[]{ new double[]{0,0,100,33.33}, new double[]{0,33.33,100,33.34}, new double[]{0,66.67,100,33.33} },
            new[]{ new double[]{0,0,50,50}, new double[]{50,0,50,50}, new double[]{0,50,50,50}, new double[]{50,50,50,50} },
            new[]{ new double[]{0,0,50,100} },
            new[]{ new double[]{50,0,50,100} },
            new[]{ new double[]{0,0,33.33,100} },
            new[]{ new double[]{33.33,0,33.34,100} },
            new[]{ new double[]{66.67,0,33.33,100} },
            new[]{ new double[]{0,0,66.67,100}, new double[]{66.67,0,33.33,100} },
            new[]{ new double[]{0,0,33.33,100}, new double[]{33.33,0,66.67,100} } };

        public SettingsWindow(List<Profile> profiles, string activeProfile, List<ProgItem> library, bool startWithWindows, bool hotkeyEnabled, bool hotkeyReady)
        {
            InitializeComponent();
            Icon = App.WindowIcon;
            result = new List<Profile>();
            foreach (Profile p in profiles) result.Add(p.Clone());
            this.library = new List<ProgItem>();
            foreach (ProgItem pi in library) this.library.Add(new ProgItem { Name = pi.Name, Exe = pi.Exe, Args = pi.Args });
            activeProfileName = activeProfile;
            hotkeyAvailable = hotkeyReady;

            StartupCheck.IsChecked = startWithWindows;
            HotkeyCheck.IsChecked = hotkeyEnabled;
            StartupCheck.Checked += delegate { dirty = true; };
            StartupCheck.Unchecked += delegate { dirty = true; };
            HotkeyCheck.Checked += delegate { dirty = true; };
            HotkeyCheck.Unchecked += delegate { dirty = true; };

            ShortcutText.Text = hotkeyAvailable ? "Ctrl + Alt + Space · ready" : hotkeyEnabled ? "Ctrl + Alt + Space · unavailable" : "Global shortcut · off";
            if (hotkeyAvailable) ShortcutText.SetResourceReference(TextBlock.ForegroundProperty, "AccentBrush");

            foreach (string name in PresetNames) PresetBox.Items.Add(name);

            WorkspaceList.SelectionChanged += delegate { OnWorkspaceSelected(); };
            AddButton.Click += delegate { AddWorkspace(); };
            RenameButton.Click += delegate { RenameWorkspace(); };
            RemoveButton.Click += delegate { RemoveWorkspace(); };

            Canvas.SelectionChanged += delegate { SyncInspector(); };
            SplitVButton.Click += delegate { Split(true); };
            SplitHButton.Click += delegate { Split(false); };
            PresetBox.SelectionChanged += delegate { OnPreset(); };
            DeleteButton.Click += delegate { DeleteZone(); };
            ResetButton.Click += delegate { ResetMonitor(); };
            ManageButton.Click += delegate { ManagePrograms(); };
            ProgBox.SelectionChanged += delegate { OnProgChanged(); };

            LeftBox.LostKeyboardFocus += delegate { OnPositionChanged(); };
            TopBox.LostKeyboardFocus += delegate { OnPositionChanged(); };
            WidthBox.LostKeyboardFocus += delegate { OnPositionChanged(); };
            HeightBox.LostKeyboardFocus += delegate { OnPositionChanged(); };

            SaveButton.Click += delegate { FinalizeSave(); closingApproved = true; RaiseSaved(); Close(); };
            CancelButton.Click += delegate { AttemptClose(); };
            Closing += delegate(object s, System.ComponentModel.CancelEventArgs e)
            {
                if (!closingApproved && dirty && !Confirm.Ask(this, "Discard unsaved changes?", "Your workspace, program, and app setting changes have not been saved.", "Discard changes", true)) e.Cancel = true;
                else closingApproved = true;
            };

            RepopulateProgramList();
            RefreshWorkspaces();
            SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
            Closed += delegate { SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged; };
        }

        void AttemptClose() { Close(); }

        void RaiseSaved()
        {
            Action<List<Profile>, List<ProgItem>, string, bool, bool> handler = Saved;
            if (handler != null) handler(result, library, activeProfileName, StartupCheck.IsChecked == true, HotkeyCheck.IsChecked == true);
        }

        void OnDisplaySettingsChanged(object sender, EventArgs e)
        {
            Dispatcher.BeginInvoke(new Action(delegate { RefreshWorkspaces(); Canvas.InvalidateVisual(); }));
        }

        public void RefreshDisplays() { RefreshWorkspaces(); Canvas.InvalidateVisual(); }

        // ---- workspace list ----

        Profile Current { get { return WorkspaceList.SelectedItem as Profile; } }

        void RefreshWorkspaces()
        {
            string selectedName = Current != null ? Current.Name : null;
            shown.Clear();
            Forms.Screen[] screens = Forms.Screen.AllScreens;
            List<string> order = new List<string>();
            Dictionary<string, List<Profile>> groups = new Dictionary<string, List<Profile>>();
            foreach (Profile p in result)
            {
                string label = Config.ProfileMonitorLabel(p, screens);
                List<Profile> members;
                if (!groups.TryGetValue(label, out members)) { members = new List<Profile>(); groups[label] = members; order.Add(label); }
                members.Add(p);
            }
            order.Sort(StringComparer.OrdinalIgnoreCase);
            List<string> front = new List<string>();
            foreach (Forms.Screen s in screens)
            {
                string label = Config.MonitorLabel(s.Bounds.Width + "x" + s.Bounds.Height);
                if (order.Remove(label)) front.Add(label);
            }
            order.InsertRange(0, front);
            foreach (string label in order)
            {
                shown.Add(new WorkspaceHeader { Label = label });
                foreach (Profile p in groups[label]) shown.Add(p);
            }

            sync = true;
            WorkspaceList.ItemsSource = null;
            WorkspaceList.ItemsSource = shown;
            sync = false;

            int sel = -1;
            if (!string.IsNullOrEmpty(selectedName))
                for (int i = 0; i < shown.Count; i++)
                    if (shown[i] is Profile p2 && string.Equals(p2.Name, selectedName, StringComparison.OrdinalIgnoreCase)) { sel = i; break; }
            if (sel < 0) sel = shown.FindIndex(x => x is Profile);
            if (sel >= 0) WorkspaceList.SelectedIndex = sel;
            else OnWorkspaceChanged();
        }

        void OnWorkspaceSelected()
        {
            if (sync) return;
            if (WorkspaceList.SelectedItem is WorkspaceHeader)
            {
                int i = WorkspaceList.SelectedIndex;
                int next = FindProfileRow(i, 1);
                if (next < 0) next = FindProfileRow(i, -1);
                if (next >= 0) WorkspaceList.SelectedIndex = next;
                return;
            }
            OnWorkspaceChanged();
        }

        int FindProfileRow(int from, int step)
        {
            for (int i = from + step; i >= 0 && i < shown.Count; i += step)
                if (shown[i] is Profile) return i;
            return -1;
        }

        void OnWorkspaceChanged()
        {
            Profile p = Current;
            Canvas.Profile = p;
            Canvas.Selected = (p != null && p.Zones.Count > 0) ? p.Zones[0] : null;
            Canvas.SelectedMon = 1;
            if (Canvas.Selected != null)
            {
                string[] monKeys = Canvas.GetMonitorKeys();
                for (int i = 0; i < monKeys.Length; i++)
                    if (Config.ZoneInSlot(Canvas.Selected, monKeys[i], i + 1)) { Canvas.SelectedMon = i + 1; break; }
            }
            Canvas.InvalidateVisual();
            SyncInspector();
        }

        void AddWorkspace()
        {
            string name = PromptWindow.Ask(this, "Name this workspace", "", n => WorkspaceNameError(n, null));
            if (string.IsNullOrEmpty(name)) return;
            result.Add(new Profile { Name = name });
            dirty = true;
            RefreshWorkspaces();
            int idx = shown.FindIndex(x => x is Profile p && string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase));
            if (idx >= 0) WorkspaceList.SelectedIndex = idx;
        }

        void RenameWorkspace()
        {
            Profile p = Current; if (p == null) return;
            string name = PromptWindow.Ask(this, "Rename workspace", p.Name, n => WorkspaceNameError(n, p));
            if (string.IsNullOrEmpty(name)) return;
            if (string.Equals(activeProfileName, p.Name, StringComparison.OrdinalIgnoreCase)) activeProfileName = name;
            p.Name = name;
            dirty = true;
            RefreshWorkspaces();
        }

        void RemoveWorkspace()
        {
            Profile p = Current; if (p == null) return;
            if (!Confirm.Ask(this, "Remove " + p.Name + "?", p.Zones.Count == 0 ? "This workspace has no zones." : "This removes its " + p.Zones.Count + " zones and app assignments when you save.", "Remove workspace", true)) return;
            bool wasActive = string.Equals(activeProfileName, p.Name, StringComparison.OrdinalIgnoreCase);
            result.Remove(p);
            if (wasActive) activeProfileName = result.Count > 0 ? result[0].Name : "";
            dirty = true;
            RefreshWorkspaces();
        }

        string WorkspaceNameError(string name, Profile current)
        {
            if (name.Length == 0) return "Enter a workspace name.";
            if (name.Length > 48) return "Use 48 characters or fewer.";
            if (name.IndexOfAny(new[] { ',', '[', ']' }) >= 0) return "Names cannot contain commas or square brackets.";
            foreach (string reserved in new[] { "Profiles", "Programs", "Panel", "Settings" })
                if (string.Equals(name, reserved, StringComparison.OrdinalIgnoreCase)) return "That name is reserved by Snappy.";
            foreach (Profile p in result)
                if (p != current && string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase)) return "A workspace with that name already exists.";
            return null;
        }

        // ---- inspector ----

        void SyncInspector()
        {
            Zone z = Canvas.Selected;
            sync = true;
            string[] monKeys = Canvas.GetMonitorKeys();
            string monKey = Canvas.SelectedMon > 0 && Canvas.SelectedMon <= monKeys.Length ? monKeys[Canvas.SelectedMon - 1] : "";
            string monLabel = Config.MonitorLabel(monKey);
            if (z == null)
            {
                SelLabel.Text = monLabel + " · no zone selected";
                SetBox(LeftBox, 0); SetBox(TopBox, 0); SetBox(WidthBox, 1); SetBox(HeightBox, 1);
                ProgBox.SelectedIndex = 0;
            }
            else
            {
                SelLabel.Text = monLabel + " · Zone " + (Canvas.Profile.Zones.IndexOf(z) + 1);
                SetBox(LeftBox, z.X); SetBox(TopBox, z.Y); SetBox(WidthBox, z.W); SetBox(HeightBox, z.H);
                int idx = string.IsNullOrEmpty(z.Prog) ? 0 : ProgBox.Items.IndexOf(z.Prog);
                ProgBox.SelectedIndex = idx >= 0 ? idx : 0;
            }
            bool has = z != null;
            LeftBox.IsEnabled = TopBox.IsEnabled = WidthBox.IsEnabled = HeightBox.IsEnabled = has;
            ProgBox.IsEnabled = DeleteButton.IsEnabled = has;
            bool hasProfile = Canvas.Profile != null;
            SplitVButton.IsEnabled = hasProfile && (z == null || z.W >= 2);
            SplitHButton.IsEnabled = hasProfile && (z == null || z.H >= 2);
            PresetBox.IsEnabled = hasProfile;
            ResetButton.IsEnabled = hasProfile && Canvas.Profile.Zones.Exists(item => Config.ZoneInSlot(item, monKey, Canvas.SelectedMon));
            if (PresetBox.SelectedIndex != -1) PresetBox.SelectedIndex = -1;
            sync = false;
        }

        static void SetBox(TextBox box, double value) { box.Text = value.ToString("0.##", CultureInfo.InvariantCulture); }

        void RepopulateProgramList()
        {
            sync = true;
            ProgBox.Items.Clear();
            ProgBox.Items.Add("(none)");
            foreach (ProgItem pi in library) ProgBox.Items.Add(pi.Name);
            Zone z = Canvas.Selected;
            int idx = (z != null && !string.IsNullOrEmpty(z.Prog)) ? ProgBox.Items.IndexOf(z.Prog) : 0;
            ProgBox.SelectedIndex = idx >= 0 ? idx : 0;
            sync = false;
        }

        void OnProgChanged()
        {
            if (sync) return;
            Zone z = Canvas.Selected; if (z == null) return;
            z.Prog = ProgBox.SelectedIndex <= 0 ? null : ProgBox.SelectedItem.ToString();
            dirty = true;
            Canvas.InvalidateVisual();
        }

        void OnPositionChanged()
        {
            if (sync) return;
            Zone z = Canvas.Selected; if (z == null) return;
            double x = ParseBox(LeftBox, z.X), y = ParseBox(TopBox, z.Y);
            double w = ParseBox(WidthBox, z.W), h = ParseBox(HeightBox, z.H);
            x = Config.Clamp(x, 0, 99); y = Config.Clamp(y, 0, 99);
            w = Config.Clamp(w, 1, 100 - x); h = Config.Clamp(h, 1, 100 - y);
            z.X = x; z.Y = y; z.W = w; z.H = h;
            dirty = true;
            sync = true; SetBox(LeftBox, x); SetBox(TopBox, y); SetBox(WidthBox, w); SetBox(HeightBox, h); sync = false;
            Canvas.InvalidateVisual();
        }

        static double ParseBox(TextBox box, double fallback)
        {
            double v;
            return double.TryParse(box.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? v : fallback;
        }

        void Renumber(Profile p) { for (int i = 0; i < p.Zones.Count; i++) p.Zones[i].Name = "Zone" + (i + 1); }

        void Split(bool vertical)
        {
            Profile p = Canvas.Profile; if (p == null) return;
            int mon = Canvas.SelectedMon;
            string[] monKeys = Canvas.GetMonitorKeys();
            string monKey = monKeys[mon - 1];
            Zone z = Canvas.Selected;
            if (z == null) { z = new Zone { Mon = mon, MonKey = monKey, X = 0, Y = 0, W = 100, H = 100 }; p.Zones.Add(z); }
            if ((vertical && z.W < 2) || (!vertical && z.H < 2)) return;
            int idx = p.Zones.IndexOf(z);
            Zone a, b;
            if (vertical)
            {
                a = new Zone { Mon = mon, MonKey = monKey, X = z.X, Y = z.Y, W = z.W / 2, H = z.H, Prog = z.Prog };
                b = new Zone { Mon = mon, MonKey = monKey, X = z.X + z.W / 2, Y = z.Y, W = z.W / 2, H = z.H };
            }
            else
            {
                a = new Zone { Mon = mon, MonKey = monKey, X = z.X, Y = z.Y, W = z.W, H = z.H / 2, Prog = z.Prog };
                b = new Zone { Mon = mon, MonKey = monKey, X = z.X, Y = z.Y + z.H / 2, W = z.W, H = z.H / 2 };
            }
            p.Zones[idx] = a; p.Zones.Insert(idx + 1, b);
            dirty = true;
            Renumber(p);
            Canvas.Selected = a; Canvas.InvalidateVisual(); SyncInspector();
        }

        void OnPreset()
        {
            if (sync || PresetBox.SelectedIndex < 0) return;
            double[][] set = PresetSets[PresetBox.SelectedIndex];
            Profile p = Canvas.Profile;
            if (p == null) { sync = true; PresetBox.SelectedIndex = -1; sync = false; return; }
            int mon = Canvas.SelectedMon;
            string[] monKeys = Canvas.GetMonitorKeys();
            string monKey = monKeys[mon - 1];
            int existing = p.Zones.Count(z => Config.ZoneInSlot(z, monKey, mon));
            sync = true; PresetBox.SelectedIndex = -1; sync = false;
            if (existing > 0 && !Confirm.Ask(this, "Replace this monitor layout?", "The preset replaces " + existing + " existing zones and their app assignments.", "Apply preset", false)) return;
            p.Zones.RemoveAll(z => Config.ZoneInSlot(z, monKey, mon));
            Zone first = null;
            foreach (double[] r in set)
            {
                Zone nz = new Zone { Mon = mon, MonKey = monKey, X = r[0], Y = r[1], W = r[2], H = r[3] };
                p.Zones.Add(nz); if (first == null) first = nz;
            }
            dirty = true;
            Renumber(p);
            Canvas.Selected = first; Canvas.InvalidateVisual(); SyncInspector();
        }

        void DeleteZone()
        {
            Profile p = Canvas.Profile; Zone z = Canvas.Selected; if (p == null || z == null) return;
            p.Zones.Remove(z); dirty = true; Renumber(p);
            Canvas.Selected = null; Canvas.InvalidateVisual(); SyncInspector();
        }

        void ResetMonitor()
        {
            Profile p = Canvas.Profile; if (p == null) return;
            int mon = Canvas.SelectedMon;
            string[] monKeys = Canvas.GetMonitorKeys();
            string monKey = monKeys[mon - 1];
            int existing = p.Zones.Count(z => Config.ZoneInSlot(z, monKey, mon));
            if (existing == 0 || !Confirm.Ask(this, "Reset " + Config.MonitorLabel(monKey) + "?", "This removes " + existing + " zones and their app assignments.", "Reset monitor", true)) return;
            p.Zones.RemoveAll(z => Config.ZoneInSlot(z, monKey, mon));
            dirty = true;
            Renumber(p);
            Canvas.Selected = null; Canvas.InvalidateVisual(); SyncInspector();
        }

        void ManagePrograms()
        {
            ProgramsWindow d = new ProgramsWindow(library, result);
            d.Owner = this;
            d.ShowDialog();
            if (d.Changed) dirty = true;
            RepopulateProgramList();
            Canvas.InvalidateVisual();
        }

        void FinalizeSave()
        {
            Forms.Screen[] screens = Forms.Screen.AllScreens;
            foreach (Profile p in result)
                for (int i = 0; i < p.Zones.Count; i++)
                {
                    Zone z = p.Zones[i];
                    if (string.IsNullOrEmpty(z.MonKey))
                    {
                        int screen = Config.ResolveScreenIndex(z, screens);
                        if (screen >= 0) z.MonKey = screens[screen].Bounds.Width + "x" + screens[screen].Bounds.Height;
                    }
                    z.Name = "Zone" + (i + 1);
                    z.X = Config.Clamp(z.X, 0, 99); z.Y = Config.Clamp(z.Y, 0, 99);
                    z.W = Config.Clamp(z.W, 1, 100 - z.X); z.H = Config.Clamp(z.H, 1, 100 - z.Y);
                }
            if (WorkspaceList.SelectedItem is Profile current) activeProfileName = current.Name;
        }
    }
}
