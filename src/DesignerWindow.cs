using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using Microsoft.Win32;

namespace Slotter
{
    // The workspace designer, Slotter's one real window. The desk fills it; workspaces are tabs
    // across the top; the selected zone and the app settings live in a drawer along the bottom.
    // Edits are staged on copies and only Save hands them to App, which owns profiles.ini.
    public sealed class DesignerWindow : Window
    {
        public event Func<List<Profile>, List<ProgItem>, string, bool, bool, bool> Saved;

        enum Mode { Wide, Medium, Stacked, Narrow }

        static readonly string[] PresetNames = {
            "Full", "2 columns", "3 columns", "4 columns", "2 rows", "3 rows", "2 × 2 grid",
            "Left ⅔ + right ⅓", "Left ⅓ + right ⅔" };

        static readonly double[][][] PresetSets = {
            new[]{ new double[]{0,0,100,100} },
            new[]{ new double[]{0,0,50,100}, new double[]{50,0,50,100} },
            new[]{ new double[]{0,0,33.33,100}, new double[]{33.33,0,33.34,100}, new double[]{66.67,0,33.33,100} },
            new[]{ new double[]{0,0,25,100}, new double[]{25,0,25,100}, new double[]{50,0,25,100}, new double[]{75,0,25,100} },
            new[]{ new double[]{0,0,100,50}, new double[]{0,50,100,50} },
            new[]{ new double[]{0,0,100,33.33}, new double[]{0,33.33,100,33.34}, new double[]{0,66.67,100,33.33} },
            new[]{ new double[]{0,0,50,50}, new double[]{50,0,50,50}, new double[]{0,50,50,50}, new double[]{50,50,50,50} },
            new[]{ new double[]{0,0,66.67,100}, new double[]{66.67,0,33.33,100} },
            new[]{ new double[]{0,0,33.33,100}, new double[]{33.33,0,66.67,100} } };

        sealed class Problem { public Profile Ws; public Zone Zone; public ProgItem Prog; public bool Name; public string Text; }
        sealed class Group { public List<MonitorInfo> Mons; public string Label; public bool AllOff; public List<Profile> Items = new List<Profile>(); }

        // State
        List<Profile> work;
        List<ProgItem> library;
        List<Profile> keptWork;
        List<ProgItem> keptLibrary;
        bool keptStartup, keptHotkey;
        string keptActive;
        string activeName;
        bool startup, hotkeyOn, hotkeyReady;
        readonly bool elevated;
        List<MonitorInfo> monitors = new List<MonitorInfo>();
        Profile current;
        Zone sel;
        string face = "zone"; // "zone", "settings", or null when the drawer is shut
        Profile renaming;
        string renameText = "";
        bool dirty, justSaved, closingApproved, sheetOpen, syncing;
        ProgItem progSel;
        Zone shownZone;
        readonly Dictionary<ProgItem, string> pendingNames = new Dictionary<ProgItem, string>();
        Mode mode = Mode.Wide;
        bool modeSet, tabsOverflow;

        // Frame
        readonly Grid root = new Grid();
        readonly Border bar = new Border();
        readonly DockPanel barRow = new DockPanel { LastChildFill = false };
        Field renameBox;
        TextBlock nameMsg;
        readonly Grid desk = new Grid { ClipToBounds = true };
        readonly DeskCanvas canvas = new DeskCanvas();
        readonly Grid docHead = new Grid { VerticalAlignment = VerticalAlignment.Top, IsHitTestVisible = false };
        readonly TextBlock title = new TextBlock(), meta = new TextBlock(), aside = new TextBlock();
        Button marginNote;
        readonly Canvas notes = new Canvas();
        readonly StackPanel firstRun = new StackPanel();
        TextBlock firstRunHead, firstRunText;
        StackPanel firstRunActions;
        Button useMonitor;
        MonitorInfo unusedMonitor;
        readonly Border drawer = new Border();
        Button dtZone, dtSet;
        readonly StackPanel commit = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        readonly DockPanel dtabs = new DockPanel();
        readonly Border faceZone = new Border(), faceSet = new Border();
        readonly Canvas floatLayer = new Canvas { IsHitTestVisible = false };
        readonly Border callout = new Border();
        readonly TextBlock calloutText = new TextBlock { TextWrapping = TextWrapping.Wrap, FontSize = 12 };

        // Zone face
        Border zChip;
        TextBlock zChipText, zTitleText, zOnText;
        StackPanel zTitle, zMini;
        TextBlock zLaunchLbl, zPosLbl, zThisLbl, zLayoutLbl, zPath, zNow, zFaultText;
        ComboBox zPicker;
        Button zManage, zReset, bSplitV, bSplitH, bDelete, mSplitV, mSplitH, mDelete;
        Field fLeft, fTop, fWidth, fHeight;
        readonly Grid zFields = new Grid();
        DockPanel zFault;
        WrapPanel zActs, zPresets;
        StackPanel zCur;
        readonly List<Button> presetButtons = new List<Button>();

        // Settings face
        ToggleButton startSw, hotSw;
        TextBlock setHead;
        readonly DockPanel hkState = new DockPanel(), elevState = new DockPanel();
        StackPanel setCol1, setCol2, setCol3;

        // Programs sheet
        readonly Grid scrim = new Grid();
        readonly Border sheet = new Border();
        readonly Grid sheetBody = new Grid();
        readonly ScrollViewer sheetList = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        readonly Border sheetListBox = new Border();
        readonly StackPanel form = new StackPanel();
        readonly ScrollViewer formScroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Field pfName, pfPath, pfArgs;
        TextBlock pfNameErr, pfPathErr, noPrograms;
        readonly WrapPanel usedBy = new WrapPanel();
        TextBlock usedNone;
        Button progRemove;
        StackPanel formFields;

        public DesignerWindow(List<Profile> profiles, string activeProfile, List<ProgItem> programs, bool startWithWindows, bool hotkeyEnabled, bool hotkeyIsReady)
        {
            Style = Ui.S("Win");
            Title = "Slotter";
            Icon = App.WindowIcon;
            Width = 1180;
            Height = 800;
            MinWidth = 640;
            MinHeight = 600;
            WindowStartupLocation = WindowStartupLocation.CenterScreen;

            work = CloneProfiles(profiles);
            library = CloneLibrary(programs);
            activeName = activeProfile ?? "";
            startup = startWithWindows;
            hotkeyOn = hotkeyEnabled;
            hotkeyReady = hotkeyIsReady;
            elevated = Presence.IsElevated();
            Keep();
            current = Config.FindProfile(work, activeName) ?? work.FirstOrDefault();
            sel = current != null ? current.Zones.FirstOrDefault() : null;
            if (current == null) face = null;

            Build();
            Content = root;
            SourceInitialized += delegate { Ui.TintTitleBar(this); };
            Closing += OnClosing;
            PreviewKeyDown += OnKey;
            root.SizeChanged += delegate { UpdateMode(); };
            root.LayoutUpdated += delegate { PlaceCallout(); };
            RenderAll();
        }

        public void RefreshDisplays() { RenderAll(); }

        public void HotkeyState(bool ready)
        {
            hotkeyReady = ready;
            RenderHead();
            SyncSettingsFace();
        }

        // ------------------------------------------------------------------ build

        void Build()
        {
            root.Background = Ui.B("B.Ground");
            root.UseLayoutRounding = true;
            TextElement.SetFontFamily(root, Ui.UiFont);
            TextElement.SetFontSize(root, Ui.D("T.Body"));
            TextElement.SetForeground(root, Ui.B("B.Ink"));
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            bar.BorderBrush = Ui.B("B.Rule");
            bar.BorderThickness = new Thickness(0, 0, 0, 1);
            bar.Child = barRow;
            Panel.SetZIndex(bar, 5);
            root.Children.Add(bar);

            BuildDesk();
            Grid.SetRow(desk, 1);
            root.Children.Add(desk);

            BuildDrawer();
            Grid.SetRow(drawer, 2);
            Panel.SetZIndex(drawer, 3);
            root.Children.Add(drawer);

            callout.Background = Ui.B("B.ErrorWash");
            callout.BorderBrush = Ui.B("B.Error");
            callout.BorderThickness = new Thickness(1);
            callout.CornerRadius = new CornerRadius(4);
            callout.Padding = new Thickness(10, 7, 10, 7);
            callout.MaxWidth = 300;
            callout.Effect = (System.Windows.Media.Effects.Effect)Ui.R("Shadow");
            callout.Child = calloutText;
            callout.Visibility = Visibility.Collapsed;
            floatLayer.Children.Add(callout);
            Grid.SetRowSpan(floatLayer, 3);
            Panel.SetZIndex(floatLayer, 30);
            root.Children.Add(floatLayer);

            BuildSheet();
            Grid.SetRowSpan(scrim, 3);
            Panel.SetZIndex(scrim, 40);
            root.Children.Add(scrim);
        }

        void BuildDesk()
        {
            desk.Background = new LinearGradientBrush(Ui.C("B.Ground"), Ui.C("B.Ground2"), new Point(0, 0), new Point(0, 1));

            canvas.ZoneClicked += delegate (Zone z) { sel = z; face = "zone"; RenderDrawer(); };
            canvas.Laid += PlaceNotes;
            canvas.Fault = CanvasFault;
            desk.Children.Add(canvas);
            desk.Children.Add(notes);

            title.FontFamily = Ui.DisplayFont;
            title.FontSize = Ui.D("T.Title");
            title.FontWeight = FontWeights.ExtraBold;
            title.LineHeight = 34;
            title.LineStackingStrategy = LineStackingStrategy.BlockLineHeight;
            title.TextTrimming = TextTrimming.CharacterEllipsis;
            meta.TextWrapping = TextWrapping.Wrap;
            StackPanel head = new StackPanel();
            head.Children.Add(title);
            head.Children.Add(meta);
            docHead.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            docHead.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            docHead.Children.Add(head);
            aside.MaxWidth = 260;
            aside.TextWrapping = TextWrapping.Wrap;
            aside.TextAlignment = TextAlignment.Right;
            aside.FontSize = 12;
            aside.Foreground = Ui.B("B.Ink3");
            aside.Margin = new Thickness(24, 6, 0, 0);
            Grid.SetColumn(aside, 1);
            docHead.Children.Add(aside);
            desk.Children.Add(docHead);

            marginNote = Ui.Button("MarginNote", "", delegate { face = "settings"; RenderDrawer(); }, "shortcut-note");
            marginNote.HorizontalAlignment = HorizontalAlignment.Right;
            marginNote.VerticalAlignment = VerticalAlignment.Bottom;
            marginNote.Margin = new Thickness(0, 0, 28, 12);
            desk.Children.Add(marginNote);

            firstRunHead = Ui.Text("Make your first workspace", 18, FontWeights.ExtraBold, "B.Ink");
            firstRunText = Ui.Text("", 12, FontWeights.Normal, "B.Ink2");
            firstRunText.TextWrapping = TextWrapping.Wrap;
            firstRunText.MaxWidth = 360;
            firstRunText.Margin = new Thickness(0, 8, 0, 0);
            Button make = Ui.Button("Btn.Primary", "New workspace", AddWorkspace, "first-workspace");
            Button progs = Ui.Button("Btn", "Add programs first", delegate { OpenSheet(null); }, "first-programs");
            firstRunActions = Ui.Row(8, make, progs);
            firstRunActions.Margin = new Thickness(0, 8, 0, 0);
            firstRun.Children.Add(firstRunHead);
            firstRun.Children.Add(firstRunText);
            firstRun.Children.Add(firstRunActions);
            notes.Children.Add(firstRun);

            useMonitor = Ui.Button("Link", "Use this monitor", delegate { if (unusedMonitor != null) UseMonitor(unusedMonitor); }, "use-monitor");
            notes.Children.Add(useMonitor);
        }

        void BuildDrawer()
        {
            Grid g = new Grid();
            g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(46) });
            g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            foreach (Border f in new[] { faceZone, faceSet })
            {
                f.Background = Ui.B("B.Drawer2");
                f.BorderBrush = Ui.B("B.Rule");
                f.BorderThickness = new Thickness(0, 1, 0, 0);
                Grid.SetRow(f, 1);
                g.Children.Add(f);
            }

            dtZone = Ui.Button("DrawerTab", "Zone", delegate { ToggleFace("zone"); }, "drawer-zone");
            dtSet = Ui.Button("DrawerTab", "Slotter settings", delegate { ToggleFace("settings"); }, "drawer-settings");
            StackPanel tabs = Ui.Row(4, dtZone, dtSet);
            tabs.VerticalAlignment = VerticalAlignment.Bottom;
            tabs.Margin = new Thickness(0, 0, 0, -1);
            DockPanel.SetDock(commit, Dock.Right);
            dtabs.Children.Add(commit);
            dtabs.Children.Add(tabs);
            dtabs.LastChildFill = false;
            g.Children.Add(dtabs);

            g.Children.Add(new Border
            {
                Width = 56, Height = 4, Background = Ui.B("B.Pull"), CornerRadius = new CornerRadius(0, 0, 3, 3),
                HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, -1, 0, 0)
            });

            drawer.Background = Ui.B("B.Drawer");
            drawer.BorderBrush = Ui.B("B.Rule");
            drawer.BorderThickness = new Thickness(0, 1, 0, 0);
            drawer.Child = g;
            AutomationProperties.SetName(drawer, "Inspector");

            BuildZoneFace();
            BuildSettingsFace();
        }

        void BuildZoneFace()
        {
            zChipText = Ui.Text("", 16, FontWeights.ExtraBold, "B.SelectionInk");
            zChipText.HorizontalAlignment = HorizontalAlignment.Center;
            zChip = new Border { Background = Ui.B("B.Selection"), CornerRadius = new CornerRadius(4), MinWidth = 28, Height = 28, Padding = new Thickness(7, 0, 7, 0), Child = zChipText };
            zTitleText = Ui.Text("", 20, FontWeights.ExtraBold, "B.Ink");
            zOnText = Ui.Text("", 13, FontWeights.Medium, "B.Ink2");
            zTitle = Ui.Row(8, zChip, zTitleText, zOnText);
            zOnText.Margin = new Thickness(6, 2, 0, 0);

            mSplitV = IconButton("G.SplitV", "Split vertically", "Btn.Icon", delegate { Split(true); }, "mini-split-v");
            mSplitH = IconButton("G.SplitH", "Split horizontally", "Btn.Icon", delegate { Split(false); }, "mini-split-h");
            mDelete = IconButton("G.Delete", "Delete zone", "Btn.IconDanger", DeleteZone, "mini-delete");
            zMini = Ui.Row(4, mSplitV, mSplitH, mDelete);
            zMini.VerticalAlignment = VerticalAlignment.Center;

            zLaunchLbl = Ui.Label("Launches");
            zPicker = new ComboBox { Style = Ui.S("Picker") };
            AutomationProperties.SetAutomationId(zPicker, "app-picker");
            AutomationProperties.SetName(zPicker, "Launches");
            zPicker.SelectionChanged += delegate { OnPick(); };
            zPath = Ui.Text("", 12, FontWeights.Normal, "B.Ink2");
            zPath.TextWrapping = TextWrapping.Wrap;
            zPath.Margin = new Thickness(0, 7, 0, 6);
            zManage = Ui.Button("Link", "Manage programs…", delegate { OpenSheet(null); }, "manage-programs");
            zManage.HorizontalAlignment = HorizontalAlignment.Left;

            zPosLbl = Ui.Label("Position and size, % of work area");
            fLeft = PositionField("Left", "pos-left", 'x');
            fTop = PositionField("Top", "pos-top", 'y');
            fWidth = PositionField("Width", "pos-width", 'w');
            fHeight = PositionField("Height", "pos-height", 'h');
            zFaultText = new TextBlock { FontSize = 12, TextWrapping = TextWrapping.Wrap, Foreground = Ui.B("B.Ink") };
            Path warn = Ui.Icon("G.Warn", 12, false, Ui.B("B.Error"));
            warn.VerticalAlignment = VerticalAlignment.Top;
            warn.Margin = new Thickness(0, 2, 8, 0);
            DockPanel.SetDock(warn, Dock.Left);
            zFault = new DockPanel { Margin = new Thickness(0, 8, 0, 0) };
            zFault.Children.Add(warn);
            zFault.Children.Add(zFaultText);

            zThisLbl = Ui.Label("This zone");
            bSplitV = LabelledButton("G.SplitV", "Split vertically", "Btn", delegate { Split(true); }, "split-v");
            bSplitH = LabelledButton("G.SplitH", "Split horizontally", "Btn", delegate { Split(false); }, "split-h");
            bDelete = LabelledButton("G.Delete", "Delete zone", "Btn.QuietDanger", DeleteZone, "delete");
            zActs = new WrapPanel();
            foreach (Button b in new[] { bSplitV, bSplitH, bDelete }) { b.Margin = new Thickness(0, 0, 6, 6); zActs.Children.Add(b); }

            zLayoutLbl = Ui.Label("Layout");
            zPresets = new WrapPanel();
            for (int i = 0; i < PresetSets.Length; i++)
            {
                int captured = i;
                Button b = Ui.Button("Preset", PresetGlyph(PresetSets[i]), delegate { ApplyPreset(captured); }, "preset-" + i);
                b.ToolTip = PresetNames[i];
                AutomationProperties.SetName(b, PresetNames[i]);
                // Gaps between the groups: columns, rows, the grid, the two uneven splits.
                b.Margin = new Thickness(i == 4 || i == 6 || i == 7 ? 6 : 0, 0, 3, 4);
                presetButtons.Add(b);
                zPresets.Children.Add(b);
            }
            zNow = Ui.Text("", 12, FontWeights.Normal, "B.Ink2");
            zReset = Ui.Button("Link", "Reset monitor", ResetMonitor, "reset-monitor");
            zCur = Ui.Row(10, zNow, zReset);
            zCur.VerticalAlignment = VerticalAlignment.Center;
        }

        Field PositionField(string label, string id, char key)
        {
            Field f = new Field { Style = Ui.S("Field.Position"), Label = label, LabelWidth = 52 };
            AutomationProperties.SetAutomationId(f, id);
            AutomationProperties.SetName(f, label + ", percent of work area");
            f.TextChanged += delegate { OnPosition(f, key); };
            f.LostKeyboardFocus += delegate { if (sel != null) { syncing = true; f.Text = Pct(Value(key)); syncing = false; } };
            return f;
        }

        Button IconButton(string icon, string name, string style, Action click, string id)
        {
            Button b = Ui.Button(style, Ui.Icon(icon, 16, false), click, id);
            b.ToolTip = name;
            AutomationProperties.SetName(b, name);
            ToolTipService.SetShowOnDisabled(b, true);
            return b;
        }

        static Button LabelledButton(string icon, string text, string style, Action click, string id)
        {
            Button b = Ui.Button(style, Ui.Row(6, Ui.Icon(icon, 16, false), new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center }), click, id);
            ToolTipService.SetShowOnDisabled(b, true);
            return b;
        }

        static Canvas PresetGlyph(double[][] rects)
        {
            Canvas c = new Canvas { Width = 24, Height = 15, SnapsToDevicePixels = true };
            Rectangle frame = new Rectangle { Width = 24, Height = 15, StrokeThickness = 1, RadiusX = 1, RadiusY = 1 };
            BindInk(frame, false);
            c.Children.Add(frame);
            // Each pane's edges land on whole logical pixels with a one-pixel gap between panes;
            // fractional edges blur together at 150% and 175% and a divider disappears.
            foreach (double[] q in rects)
            {
                double left = Math.Round(2 + q[0] * 0.2), right = Math.Round(2 + (q[0] + q[2]) * 0.2) - 1;
                double top = Math.Round(2 + q[1] * 0.11), bottom = Math.Round(2 + (q[1] + q[3]) * 0.11) - 1;
                Rectangle r = new Rectangle { Width = Math.Max(1, right - left), Height = Math.Max(1, bottom - top) };
                BindInk(r, true);
                Canvas.SetLeft(r, left);
                Canvas.SetTop(r, top);
                c.Children.Add(r);
            }
            return c;
        }

        static void BindInk(Shape s, bool fill)
        {
            System.Windows.Data.Binding ink = new System.Windows.Data.Binding("Foreground")
            {
                RelativeSource = new System.Windows.Data.RelativeSource(System.Windows.Data.RelativeSourceMode.FindAncestor, typeof(Control), 1)
            };
            s.SetBinding(fill ? Shape.FillProperty : Shape.StrokeProperty, ink);
        }

        void BuildSettingsFace()
        {
            setHead = Ui.Text("Slotter settings", 20, FontWeights.ExtraBold, "B.Ink");
            setHead.Margin = new Thickness(0, 0, 0, 10);

            startSw = new ToggleButton { Style = Ui.S("Switch") };
            AutomationProperties.SetAutomationId(startSw, "start-with-windows");
            AutomationProperties.SetName(startSw, "Start with Windows");
            startSw.Click += delegate { if (!syncing) { startup = startSw.IsChecked == true; Touch(); } };
            hotSw = new ToggleButton { Style = Ui.S("Switch") };
            AutomationProperties.SetAutomationId(hotSw, "launch-shortcut");
            AutomationProperties.SetName(hotSw, "Global launch shortcut");
            hotSw.Click += delegate { if (!syncing) { hotkeyOn = hotSw.IsChecked == true; Touch(); RenderHead(); SyncSettingsFace(); } };

            StackPanel startText = new StackPanel();
            startText.Children.Add(Ui.Text("Start with Windows", 13, FontWeights.Bold, "B.Ink"));
            TextBlock startSub = Ui.Text("Sits in the tray from sign-in, elevated, so admin windows snap too.", 12, FontWeights.Normal, "B.Ink2");
            startSub.TextWrapping = TextWrapping.Wrap;
            startText.Children.Add(startSub);
            setCol1 = new StackPanel();
            setCol1.Children.Add(setHead);
            setCol1.Children.Add(SettingRow(startText, startSw));

            StackPanel hkText = new StackPanel();
            hkText.Children.Add(Ui.Text("Global launch shortcut", 13, FontWeights.Bold, "B.Ink"));
            hkText.Children.Add(Ui.Kbd("Ctrl + Alt + Space"));
            hkText.Children.Add(hkState);
            setCol2 = new StackPanel();
            setCol2.Children.Add(SettingRow(hkText, hotSw));

            StackPanel elevText = new StackPanel();
            elevText.Children.Add(Ui.Text("Administrator rights", 13, FontWeights.Bold, "B.Ink"));
            elevText.Children.Add(elevState);
            setCol3 = new StackPanel();
            setCol3.Children.Add(SettingRow(elevText, null));
            Button manage = Ui.Button("Btn.Quiet", "Manage programs…", delegate { OpenSheet(null); }, "settings-programs");
            manage.HorizontalAlignment = HorizontalAlignment.Left;
            manage.Margin = new Thickness(-12, 0, 0, 0);
            setCol3.Children.Add(manage);
        }

        static DockPanel SettingRow(UIElement text, UIElement control)
        {
            DockPanel row = new DockPanel { Margin = new Thickness(0, 0, 0, 10) };
            if (control != null)
            {
                DockPanel.SetDock(control, Dock.Right);
                ((FrameworkElement)control).Margin = new Thickness(10, 0, 0, 0);
                row.Children.Add(control);
            }
            row.Children.Add(text);
            return row;
        }

        void BuildSheet()
        {
            scrim.Background = Ui.B("B.Scrim");
            scrim.Visibility = Visibility.Collapsed;
            scrim.SizeChanged += delegate { SizeSheet(); };

            StackPanel headText = new StackPanel();
            headText.Children.Add(Ui.Text("Programs", 20, FontWeights.ExtraBold, "B.Ink"));
            TextBlock lede = Ui.Text("Defined once, picked by every zone. Renaming one renames it in every zone that uses it.", 12, FontWeights.Normal, "B.Ink2");
            lede.TextWrapping = TextWrapping.Wrap;
            lede.Margin = new Thickness(0, 4, 0, 0);
            headText.Children.Add(lede);
            Border head = new Border { Padding = new Thickness(22, 18, 22, 12), BorderBrush = Ui.B("B.Rule"), BorderThickness = new Thickness(0, 0, 0, 1), Child = headText };
            DockPanel.SetDock(head, Dock.Top);

            Button add = Ui.Button("Btn", Ui.Row(6, Ui.Icon("G.Plus", 12, false, 1.6), new TextBlock { Text = "Add program", VerticalAlignment = VerticalAlignment.Center }), AddProgram, "prog-add");
            progRemove = Ui.Button("Btn.Danger", "Remove", RemoveProgram, "prog-remove");
            progRemove.Margin = new Thickness(8, 0, 0, 0);
            Button done = Ui.Button("Btn.Primary", "Done", CloseSheet, "prog-done");
            DockPanel footRow = new DockPanel { LastChildFill = false };
            DockPanel.SetDock(done, Dock.Right);
            footRow.Children.Add(done);
            footRow.Children.Add(add);
            footRow.Children.Add(progRemove);
            Border foot = new Border { Padding = new Thickness(22, 12, 22, 12), BorderBrush = Ui.B("B.Rule"), BorderThickness = new Thickness(0, 1, 0, 0), Child = footRow };
            DockPanel.SetDock(foot, Dock.Bottom);

            sheetListBox.BorderBrush = Ui.B("B.Rule");
            sheetListBox.Child = sheetList;

            pfName = SheetField("prog-name");
            pfName.TextChanged += delegate { OnProgramName(); };
            pfPath = SheetField("prog-path");
            pfPath.TextChanged += delegate { if (syncing || progSel == null) return; progSel.Exe = pfPath.Text.Trim(); Touch(); SyncProgramErrors(); canvas.Refresh(); };
            pfArgs = SheetField("prog-args");
            pfArgs.TextChanged += delegate { if (syncing || progSel == null) return; progSel.Args = pfArgs.Text.Trim(); Touch(); };
            pfNameErr = ErrorLine();
            pfPathErr = ErrorLine();
            Button browse = Ui.Button("Btn", "Browse…", Browse, "prog-browse");
            browse.Height = 34;
            browse.Margin = new Thickness(6, 0, 0, 0);
            DockPanel.SetDock(browse, Dock.Right);
            DockPanel pathRow = new DockPanel();
            pathRow.Children.Add(browse);
            pathRow.Children.Add(pfPath);
            TextBlock hint = Ui.Text("An .exe, or a .lnk shortcut to one.", 11, FontWeights.Normal, "B.Ink2");
            hint.Margin = new Thickness(0, 4, 0, 0);
            usedNone = Ui.Text("No zone yet.", 12, FontWeights.Normal, "B.Ink2");

            formFields = new StackPanel();
            formFields.Children.Add(FormGroup(Ui.Label("Name"), pfName, pfNameErr));
            formFields.Children.Add(FormGroup(Ui.Label("Executable or app"), pathRow, hint, pfPathErr));
            formFields.Children.Add(FormGroup(Ui.Label("Arguments, optional"), pfArgs));
            formFields.Children.Add(FormGroup(Ui.Label("Used by"), usedBy, usedNone));
            noPrograms = Ui.Text("No programs yet. Add one to give zones something to launch.", 12, FontWeights.Normal, "B.Ink2");
            noPrograms.TextWrapping = TextWrapping.Wrap;
            form.Children.Add(formFields);
            form.Children.Add(noPrograms);
            formScroll.Content = form;

            sheetBody.Children.Add(sheetListBox);
            sheetBody.Children.Add(formScroll);

            DockPanel sd = new DockPanel();
            sd.Children.Add(head);
            sd.Children.Add(foot);
            sd.Children.Add(sheetBody);

            sheet.Background = Ui.B("B.Sheet");
            sheet.BorderBrush = Ui.B("B.FieldBorder");
            sheet.BorderThickness = new Thickness(1, 0, 1, 1);
            sheet.CornerRadius = (CornerRadius)Ui.R("R.Sheet");
            sheet.Effect = (System.Windows.Media.Effects.Effect)Ui.R("Shadow");
            sheet.HorizontalAlignment = HorizontalAlignment.Center;
            sheet.VerticalAlignment = VerticalAlignment.Top;
            sheet.Child = sd;
            AutomationProperties.SetName(sheet, "Programs");
            scrim.Children.Add(sheet);
        }

        static Field SheetField(string id)
        {
            Field f = new Field { Style = Ui.S("Field") };
            AutomationProperties.SetAutomationId(f, id);
            return f;
        }

        static TextBlock ErrorLine()
        {
            TextBlock t = Ui.Text("", 12, FontWeights.SemiBold, "B.Error");
            t.TextWrapping = TextWrapping.Wrap;
            t.Margin = new Thickness(0, 4, 0, 0);
            t.Visibility = Visibility.Collapsed;
            return t;
        }

        static StackPanel FormGroup(params UIElement[] items)
        {
            StackPanel s = new StackPanel { Margin = new Thickness(0, 0, 0, 12) };
            foreach (UIElement e in items) s.Children.Add(e);
            return s;
        }

        // ------------------------------------------------------------------ modes

        // Below 1000 the tabs become a switcher and the drawer drops the program path, below 860
        // the zone's shape column moves under the other two, and below 760 the drawer reflows to
        // four rows and the margin notes go.
        void UpdateMode()
        {
            double w = root.ActualWidth;
            if (w <= 0) return;
            Mode m = w < 760 ? Mode.Narrow : w < 860 ? Mode.Stacked : w < 1000 ? Mode.Medium : Mode.Wide;
            bool changed = !modeSet || m != mode;
            mode = m;
            modeSet = true;
            tabsOverflow = false;
            if (changed) { ApplyMode(); RenderAll(); }
            else RenderBar();
            if (sheetOpen) SizeSheet();
        }

        void ApplyMode()
        {
            bool narrow = mode == Mode.Narrow;
            bar.Height = narrow ? 46 : 48;
            bar.Padding = narrow ? new Thickness(12, 0, 10, 0) : new Thickness(20, 0, 16, 0);
            docHead.Margin = narrow ? new Thickness(14, 6, 14, 0) : new Thickness(32, 16, 32, 0);
            meta.Margin = narrow ? new Thickness(0) : new Thickness(0, 4, 0, 0);
            canvas.Margin = notes.Margin = new Thickness(0, narrow ? 24 : 84, 0, 0);
            canvas.Narrow = narrow;
            dtabs.Margin = narrow ? new Thickness(12, 0, 12, 0) : new Thickness(24, 0, 16, 0);
            faceZone.Padding = faceSet.Padding = narrow ? new Thickness(14, 10, 14, 12)
                : mode == Mode.Wide ? new Thickness(32, 14, 32, 18) : new Thickness(20, 14, 20, 18);
            marginNote.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
            ArrangeZoneFace();
            ArrangeSettingsFace();
            ArrangeSheet();
        }

        void ArrangeZoneFace()
        {
            UIElement[] parts = { zTitle, zMini, zLaunchLbl, zPicker, zPath, zManage, zPosLbl, zFields, zFault, zThisLbl, zActs, zLayoutLbl, zPresets, zCur };
            foreach (UIElement e in parts) Ui.Detach(e);
            bool narrow = mode == Mode.Narrow;

            zTitleText.FontSize = narrow ? 16 : 20;
            zChip.Height = narrow ? 22 : 28;
            zChip.MinWidth = narrow ? 22 : 28;
            zChipText.FontSize = narrow ? 13 : 16;
            zPicker.Height = narrow ? 34 : 40;
            zPicker.FontSize = narrow ? 15 : 16;
            zTitle.Margin = new Thickness(0, 0, 0, narrow ? 0 : 10);
            zManage.Margin = narrow ? new Thickness(10, 0, 0, 0) : new Thickness(0);
            zCur.Margin = narrow ? new Thickness(4, 0, 0, 4) : new Thickness(0);
            zPresets.Margin = new Thickness(0, 0, 0, narrow ? 0 : 6);
            zMini.Margin = new Thickness(0);
            // At medium width the icon buttons share the title's line; the drawer tab already names the monitor.
            zOnText.Visibility = mode == Mode.Medium ? Visibility.Collapsed : Visibility.Visible;
            foreach (Field f in new[] { fLeft, fTop, fWidth, fHeight }) f.LabelWidth = mode == Mode.Wide ? 52 : 0;
            LayoutFields(narrow);

            if (narrow)
            {
                StackPanel col = new StackPanel();
                Grid r1 = new Grid();
                r1.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                r1.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                zTitle.VerticalAlignment = VerticalAlignment.Center;
                r1.Children.Add(zTitle);
                Grid.SetColumn(zMini, 1);
                r1.Children.Add(zMini);
                Grid r2 = new Grid { Margin = new Thickness(0, 8, 0, 0) };
                r2.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                r2.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                r2.Children.Add(zPicker);
                Grid.SetColumn(zManage, 1);
                r2.Children.Add(zManage);
                zFields.Margin = new Thickness(0, 8, 0, 0);
                WrapPanel r4 = new WrapPanel { Margin = new Thickness(0, 8, 0, 0) };
                r4.Children.Add(zPresets);
                r4.Children.Add(zCur);
                col.Children.Add(r1);
                col.Children.Add(r2);
                col.Children.Add(zFields);
                col.Children.Add(zFault);
                col.Children.Add(r4);
                faceZone.Child = col;
                return;
            }

            zFields.Margin = new Thickness(0);
            Grid g = new Grid();
            if (mode == Mode.Wide)
            {
                AddColumn(g, 1.25, 230, Stack(zTitle, zLaunchLbl, zPicker, zPath, zManage), 0, false);
                AddColumn(g, 1, 250, Stack(zPosLbl, zFields, zFault), 1, false);
                AddColumn(g, 1.2, 300, Stack(zThisLbl, zActs, new Border { Height = 4 }, zLayoutLbl, zPresets, zCur), 2, true);
            }
            else if (mode == Mode.Medium)
            {
                // Three columns still fit here once the split and delete buttons shrink to icons
                // beside the zone title, which keeps the drawer short and the desk dominant.
                Grid head = new Grid { Margin = new Thickness(0, 0, 0, 10) };
                head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                zTitle.Margin = new Thickness(0);
                zTitle.VerticalAlignment = VerticalAlignment.Center;
                head.Children.Add(zTitle);
                Grid.SetColumn(zMini, 1);
                zMini.Margin = new Thickness(8, 0, 0, 0);
                head.Children.Add(zMini);
                zManage.Margin = new Thickness(0, 7, 0, 0);
                AddColumn(g, 1.1, 0, Stack(head, zLaunchLbl, zPicker, zManage), 0, false, 16);
                AddColumn(g, 1.2, 0, Stack(zPosLbl, zFields, zFault), 1, false, 16);
                AddColumn(g, 1, 0, Stack(zLayoutLbl, zPresets, zCur), 2, true, 16);
            }
            else
            {
                AddColumn(g, 1, 0, Stack(zTitle, zLaunchLbl, zPicker, zManage), 0, false);
                AddColumn(g, 1, 0, Stack(zPosLbl, zFields, zFault), 1, true);
                zManage.Margin = new Thickness(0, 7, 0, 0);
                g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                Border below = new Border
                {
                    BorderBrush = Ui.B("B.Rule"), BorderThickness = new Thickness(0, 1, 0, 0),
                    Padding = new Thickness(0, 12, 0, 0), Margin = new Thickness(0, 12, 0, 0),
                    Child = Stack(zThisLbl, zActs, new Border { Height = 4 }, zLayoutLbl, zPresets, zCur)
                };
                Grid.SetRow(below, 1);
                Grid.SetColumnSpan(below, 2);
                g.Children.Add(below);
            }
            faceZone.Child = g;
        }

        static StackPanel Stack(params UIElement[] items)
        {
            StackPanel s = new StackPanel();
            foreach (UIElement e in items) s.Children.Add(e);
            return s;
        }

        static void AddColumn(Grid g, double weight, double min, UIElement content, int index, bool last, double gutter = 24)
        {
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(weight, GridUnitType.Star), MinWidth = min });
            bool rule = index > 0;
            Border b = new Border
            {
                BorderBrush = Ui.B("B.Rule"), BorderThickness = new Thickness(rule ? 1 : 0, 0, 0, 0),
                Padding = new Thickness(index == 0 ? 0 : gutter, 0, last ? 0 : gutter, 0), Child = content
            };
            Grid.SetColumn(b, index);
            g.Children.Add(b);
        }

        void LayoutFields(bool oneRow)
        {
            zFields.Children.Clear();
            zFields.ColumnDefinitions.Clear();
            zFields.RowDefinitions.Clear();
            Field[] fs = { fLeft, fTop, fWidth, fHeight };
            int cols = oneRow ? 4 : 2;
            double gap = oneRow ? 6 : 8;
            for (int c = 0; c < cols; c++) zFields.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            for (int r = 0; r < 4 / cols; r++) zFields.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            for (int i = 0; i < 4; i++)
            {
                int c = i % cols, r = i / cols;
                fs[i].Margin = new Thickness(c == 0 ? 0 : gap / 2, r == 0 ? 0 : gap, c == cols - 1 ? 0 : gap / 2, 0);
                Grid.SetColumn(fs[i], c);
                Grid.SetRow(fs[i], r);
                zFields.Children.Add(fs[i]);
            }
        }

        void ArrangeSettingsFace()
        {
            foreach (UIElement e in new UIElement[] { setCol1, setCol2, setCol3 }) Ui.Detach(e);
            bool narrow = mode == Mode.Narrow;
            setHead.FontSize = narrow ? 16 : 20;
            setHead.Margin = new Thickness(0, 0, 0, narrow ? 6 : 10);
            if (narrow)
            {
                faceSet.Child = Stack(setCol1, setCol2, setCol3);
                return;
            }
            Grid g = new Grid();
            AddColumn(g, 1, 0, setCol1, 0, false);
            AddColumn(g, 1, 0, setCol2, 1, false);
            AddColumn(g, 1, 0, setCol3, 2, true);
            faceSet.Child = g;
        }

        void ArrangeSheet()
        {
            bool narrow = mode == Mode.Narrow;
            sheetBody.ColumnDefinitions.Clear();
            sheetBody.RowDefinitions.Clear();
            if (narrow)
            {
                sheetBody.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                sheetBody.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
                Grid.SetColumn(sheetListBox, 0); Grid.SetRow(sheetListBox, 0);
                Grid.SetColumn(formScroll, 0); Grid.SetRow(formScroll, 1);
                sheetListBox.BorderThickness = new Thickness(0, 0, 0, 1);
                sheetListBox.Padding = new Thickness(12, 8, 12, 4);
                form.Margin = new Thickness(16, 12, 16, 0);
            }
            else
            {
                sheetBody.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(200) });
                sheetBody.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                Grid.SetColumn(sheetListBox, 0); Grid.SetRow(sheetListBox, 0);
                Grid.SetColumn(formScroll, 1); Grid.SetRow(formScroll, 0);
                sheetListBox.BorderThickness = new Thickness(0, 0, 1, 0);
                sheetListBox.Padding = new Thickness(8);
                form.Margin = new Thickness(22, 16, 22, 4);
            }
        }

        void SizeSheet()
        {
            double w = scrim.ActualWidth, h = scrim.ActualHeight;
            if (w <= 0) return;
            sheet.Width = mode == Mode.Narrow ? Math.Max(0, w - 16) : Math.Min(680, w - 32);
            sheet.MaxHeight = Math.Max(0, h - 24);
        }

        // ------------------------------------------------------------------ render

        void RenderAll()
        {
            monitors = Monitors.Known(work);
            if (current != null && !work.Contains(current)) current = work.FirstOrDefault();
            if (sel != null && (current == null || !current.Zones.Contains(sel))) sel = null;
            if (sel == null && current != null) sel = current.Zones.FirstOrDefault();
            RenderBar();
            RenderHead();
            canvas.Monitors = monitors;
            canvas.Profile = current;
            canvas.Selected = sel;
            canvas.Library = library;
            canvas.Refresh();
            RenderDrawer();
            RenderCommit();
            if (sheetOpen) RenderSheet();
        }

        void RenderBar()
        {
            barRow.Children.Clear();
            barRow.LastChildFill = false;
            renameBox = null;
            nameMsg = null;
            if (mode == Mode.Wide && !tabsOverflow)
            {
                StackPanel tabs = BuildTabs();
                Button add = Ui.Button("Tab.Add", Ui.Row(6, Ui.Icon("G.Plus", 12, false, 1.6), new TextBlock { Text = "New workspace", VerticalAlignment = VerticalAlignment.Center }), AddWorkspace, "ws-add");
                add.Margin = new Thickness(10, 0, 0, 0);
                barRow.Children.Add(tabs);
                barRow.Children.Add(add);
                double have = root.ActualWidth - bar.Padding.Left - bar.Padding.Right;
                tabs.Measure(new Size(double.PositiveInfinity, 48));
                add.Measure(new Size(double.PositiveInfinity, 48));
                if (have > 0 && tabs.DesiredSize.Width + add.DesiredSize.Width + 10 > have)
                {
                    tabsOverflow = true;
                    RenderBar();
                    return;
                }
            }
            else if (renaming != null) barRow.Children.Add(NameRow());
            else barRow.Children.Add(SwitcherButton());
            RenameFault();
        }

        StackPanel BuildTabs()
        {
            StackPanel row = new StackPanel { Orientation = Orientation.Horizontal };
            AutomationProperties.SetName(row, "Workspaces");
            bool first = true;
            foreach (Group g in Groups())
            {
                string label = (g.Label + (g.AllOff ? " · disconnected" : "")).ToUpperInvariant();
                StackPanel head = Ui.Row(6, Pictogram(g.Mons), Ui.Text(label, 11, FontWeights.Normal, "B.Ink3"));
                head.Margin = new Thickness(first ? 0 : 14, 0, 6, 0);
                head.VerticalAlignment = VerticalAlignment.Center;
                first = false;
                row.Children.Add(head);
                foreach (Profile ws in g.Items) row.Children.Add(TabFor(ws));
            }
            return row;
        }

        UIElement TabFor(Profile ws)
        {
            if (ws == renaming)
            {
                Field f = RenameField(150);
                f.Margin = new Thickness(6, 0, 6, 0);
                return f;
            }
            bool on = ws == current;
            Grid tab = new Grid();
            tab.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            tab.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            StackPanel words = Ui.Row(7, new TextBlock { Text = ws.Name, VerticalAlignment = VerticalAlignment.Center }, AllOffline(ws) ? Ui.Tag("Offline") : null);
            Button b = Ui.Button("Tab", words, delegate { SelectWorkspace(ws); }, "ws-" + ws.Name);
            b.Tag = on ? "on" : null;
            AutomationProperties.SetName(b, ws.Name);
            tab.Children.Add(b);
            if (on)
            {
                Path dots = new Path { Data = Ui.G("G.More"), Width = 14, Height = 4 };
                BindInk(dots, true);
                Button more = Ui.Button("Tab.More", dots, null, "ws-more");
                more.Click += delegate { OpenWorkspaceMenu(more); };
                more.Margin = new Thickness(0, 0, 4, 0);
                more.ToolTip = "Rename or remove " + ws.Name;
                AutomationProperties.SetName(more, "Options for " + ws.Name);
                Grid.SetColumn(more, 1);
                tab.Children.Add(more);
                Border underline = new Border { Height = 3, Background = Ui.B("B.Selection"), VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(8, 0, 8, -1) };
                Grid.SetColumnSpan(underline, 2);
                tab.Children.Add(underline);
            }
            return tab;
        }

        Field RenameField(double width)
        {
            Field f = new Field { Style = Ui.S("Field"), Width = width, Height = 30, FontSize = 14, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
            AutomationProperties.SetAutomationId(f, "rename");
            AutomationProperties.SetName(f, "Rename " + renaming.Name);
            syncing = true;
            f.Text = renameText;
            syncing = false;
            f.TextChanged += delegate
            {
                if (syncing) return;
                renameText = f.Text;
                if (renameText.Trim() != renaming.Name) { dirty = true; justSaved = false; }
                RenameFault();
                RenderCommit();
            };
            f.KeyDown += delegate (object s, KeyEventArgs e)
            {
                if (e.Key == Key.Enter) { CommitRename(true); e.Handled = true; }
                else if (e.Key == Key.Escape) { renaming = null; RenderAll(); e.Handled = true; }
            };
            renameBox = f;
            return f;
        }

        UIElement NameRow()
        {
            DockPanel row = new DockPanel { VerticalAlignment = VerticalAlignment.Center };
            TextBlock label = Ui.Text("Rename " + renaming.Name, 12, FontWeights.Normal, "B.Ink2");
            label.Margin = new Thickness(0, 0, 10, 0);
            DockPanel.SetDock(label, Dock.Left);
            Field f = RenameField(140);
            DockPanel.SetDock(f, Dock.Left);
            nameMsg = new TextBlock { FontSize = 12, TextWrapping = TextWrapping.Wrap, LineHeight = 15, LineStackingStrategy = LineStackingStrategy.BlockLineHeight, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(10, 0, 0, 0) };
            row.Children.Add(label);
            row.Children.Add(f);
            row.Children.Add(nameMsg);
            barRow.LastChildFill = true;
            return row;
        }

        void RenameFault()
        {
            string err = renaming == null ? null : NameError(renameText, renaming);
            if (renameBox != null) renameBox.Faulted = err != null;
            if (nameMsg != null)
            {
                nameMsg.Inlines.Clear();
                if (err != null) nameMsg.Inlines.Add(Ui.Run(err, "B.Error", FontWeights.Bold));
                else nameMsg.Inlines.Add(Ui.Run("Press Enter to keep it.", "B.Ink2", FontWeights.Normal));
            }
            bool show = err != null && renameBox != null && nameMsg == null;
            callout.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
            if (show)
            {
                calloutText.Inlines.Clear();
                calloutText.Inlines.Add(Ui.Run("Cannot rename " + renaming.Name + ".", "B.Error", FontWeights.Bold));
                calloutText.Inlines.Add(Ui.Run(" " + err, "B.Ink", FontWeights.Normal));
            }
        }

        void PlaceCallout()
        {
            if (callout.Visibility != Visibility.Visible || renameBox == null || !renameBox.IsDescendantOf(root)) return;
            try
            {
                Point p = renameBox.TranslatePoint(new Point(0, renameBox.ActualHeight + 6), floatLayer);
                if (Math.Abs(Canvas.GetLeft(callout) - p.X) > 0.5 || double.IsNaN(Canvas.GetLeft(callout))) Canvas.SetLeft(callout, p.X);
                if (Math.Abs(Canvas.GetTop(callout) - p.Y) > 0.5 || double.IsNaN(Canvas.GetTop(callout))) Canvas.SetTop(callout, p.Y);
            }
            catch (InvalidOperationException) { }
        }

        UIElement SwitcherButton()
        {
            DockPanel content = new DockPanel();
            Path chev = Ui.Icon("G.Chevron", 10, false, 1.6);
            chev.Margin = new Thickness(8, 0, 0, 0);
            DockPanel.SetDock(chev, Dock.Right);
            string capText = current == null ? "" : AllOffline(current) ? "offline" : GroupLabel(MonitorsOf(current));
            TextBlock cap = Ui.Text(capText, 11, FontWeights.Normal, "B.Ink3");
            cap.Margin = new Thickness(8, 1, 0, 0);
            DockPanel.SetDock(cap, Dock.Right);
            TextBlock name = Ui.Text(current != null ? current.Name : "No workspaces", 15, FontWeights.Bold, "B.Ink");
            name.TextTrimming = TextTrimming.CharacterEllipsis;
            content.Children.Add(chev);
            content.Children.Add(cap);
            content.Children.Add(name);
            Button b = Ui.Button("Switcher", content, null, "ws-switcher");
            b.Click += delegate { OpenSwitcherMenu(b); };
            b.VerticalAlignment = VerticalAlignment.Center;
            AutomationProperties.SetName(b, "Workspace: " + (current != null ? current.Name : "none"));
            return b;
        }

        void RenderHead()
        {
            bool narrow = mode == Mode.Narrow;
            title.Text = current != null ? current.Name : "No workspaces yet";
            title.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
            meta.FontSize = narrow ? 12 : 13;
            meta.Foreground = Ui.B("B.Ink2");
            List<MonitorInfo> online = monitors.Where(m => m.Online).ToList();
            if (current == null)
            {
                string found = "First run. " + CountWords(online.Count) + " found";
                meta.Text = narrow || online.Count == 0 ? found + "." : found + ": " + Names(online) + ".";
            }
            else
            {
                List<MonitorInfo> gone = MonitorsOf(current).Where(m => !m.Online).ToList();
                if (gone.Count > 0)
                {
                    meta.Foreground = Ui.B("B.Error");
                    string names = Names(gone);
                    meta.Text = narrow ? names + " disconnected. Edits are kept."
                        : gone.Count == 1 ? names + " is disconnected. Its zones stay editable and fill when it returns."
                        : names + " are disconnected. Their zones stay editable and fill when they return.";
                }
                else
                {
                    int zones = current.Zones.Count, apps = current.Zones.Count(z => !string.IsNullOrEmpty(z.Prog));
                    string counts = zones + (zones == 1 ? " zone, " : " zones, ") + (apps == 1 ? "1 with an app" : apps + " with apps");
                    meta.Text = narrow ? counts + " · " + (DeskLayout.For(monitors).TrueSize ? "drawn at true size" : "drawn to pixel scale")
                        : GroupLabel(MonitorsOf(current)) + " · " + counts;
                }
            }
            aside.Text = AsideText(online);
            aside.Visibility = narrow || aside.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;

            TextBlock note = new TextBlock();
            if (!hotkeyOn) note.Text = "Ctrl + Alt + Space off";
            else if (!keptHotkey) note.Text = "Ctrl + Alt + Space turns on when you save";
            else if (hotkeyReady) note.Text = "Ctrl + Alt + Space ready";
            else { note.Text = "Ctrl + Alt + Space unavailable"; note.Foreground = Ui.B("B.Error"); note.FontWeight = FontWeights.SemiBold; }
            marginNote.Content = note;
            AutomationProperties.SetName(marginNote, note.Text + ". Opens Slotter settings.");
        }

        string AsideText(List<MonitorInfo> online)
        {
            if (online.Count == 0) return "";
            DeskLayout d = DeskLayout.For(monitors);
            if (d.TrueSize)
            {
                List<string> parts = monitors.Where(m => m.HasSize).Select(m => "the " + m.Diagonal + " in " + m.Name).ToList();
                return "Drawn at true size: " + JoinAnd(parts) + (parts.Count == 1 ? " as it stands on the desk." : " as they stand on the desk.");
            }
            MonitorInfo blind = online.FirstOrDefault(m => !m.HasSize);
            return blind == null ? "" : "Drawn to pixel scale, because " + blind.Name + " does not report its physical size.";
        }

        void PlaceNotes()
        {
            bool narrow = mode == Mode.Narrow;
            if (current == null)
            {
                int online = monitors.Count(m => m.Online);
                firstRunText.Text = "A workspace is a named set of apps, each opened into a zone on one of these monitors. "
                    + (online == 1 ? "It is connected and ready." : online == 2 ? "Both are connected and ready." : "All are connected and ready.");
                firstRun.Visibility = Visibility.Visible;
                HorizontalAlignment align = narrow ? HorizontalAlignment.Left : HorizontalAlignment.Center;
                firstRunHead.HorizontalAlignment = firstRunText.HorizontalAlignment = firstRunActions.HorizontalAlignment = align;
                firstRunText.TextAlignment = narrow ? TextAlignment.Left : TextAlignment.Center;
                firstRunText.MaxWidth = narrow ? 520 : 360;
                firstRunHead.FontSize = narrow ? 20 : 18;
                DeskCanvas.Placed host = canvas.Placements.FirstOrDefault(p => p.Monitor.Online) ?? canvas.Placements.FirstOrDefault();
                if (narrow || host == null)
                {
                    firstRun.Width = Math.Max(0, notes.ActualWidth - 28);
                    Canvas.SetLeft(firstRun, 14);
                    Canvas.SetTop(firstRun, 6);
                }
                else
                {
                    Rect r = host.Screen;
                    firstRun.Width = Math.Max(0, r.Width - 32);
                    firstRun.Measure(new Size(firstRun.Width, double.PositiveInfinity));
                    Canvas.SetLeft(firstRun, r.X + 16);
                    Canvas.SetTop(firstRun, r.Y + Math.Max(4, (r.Height - firstRun.DesiredSize.Height) / 2));
                }
            }
            else firstRun.Visibility = Visibility.Collapsed;

            // The shortcut note sits in the bottom-right margin; when the rightmost monitor's plate
            // reaches it (medium widths), it goes, since Slotter settings says the same.
            bool noteFits = mode != Mode.Narrow;
            if (noteFits && canvas.Placements.Count > 0)
            {
                marginNote.Visibility = Visibility.Visible;
                marginNote.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
                double plateRight = canvas.Placements.Max(p => p.Plate.X + p.PlateHalf);
                noteFits = plateRight + 16 < notes.ActualWidth - marginNote.Margin.Right - marginNote.DesiredSize.Width;
            }
            marginNote.Visibility = noteFits ? Visibility.Visible : Visibility.Collapsed;

            unusedMonitor = null;
            DeskCanvas.Placed unused = current == null ? null : canvas.Placements.FirstOrDefault(p => !p.Used);
            if (unused != null && unused.Screen.Height >= 64)
            {
                unusedMonitor = unused.Monitor;
                useMonitor.Visibility = Visibility.Visible;
                useMonitor.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
                Canvas.SetLeft(useMonitor, unused.Screen.X + (unused.Screen.Width - useMonitor.DesiredSize.Width) / 2);
                Canvas.SetTop(useMonitor, unused.Screen.Y + unused.Screen.Height / 2 + 4);
            }
            else useMonitor.Visibility = Visibility.Collapsed;
        }

        void ToggleFace(string f)
        {
            face = face == f ? null : f;
            RenderDrawer();
        }

        void RenderDrawer()
        {
            if (current == null || sel == null)
            {
                dtZone.IsEnabled = false;
                dtZone.Content = "Zone: none yet";
                if (face == "zone") face = null;
            }
            else
            {
                MonitorInfo m = MonitorOf(sel);
                dtZone.IsEnabled = true;
                dtZone.Content = "Zone " + (current.Zones.IndexOf(sel) + 1) + " on " + (m != null ? m.Name : "an unknown monitor");
            }
            dtZone.Tag = face == "zone" ? "on" : null;
            dtSet.Tag = face == "settings" ? "on" : null;
            faceZone.Visibility = face == "zone" ? Visibility.Visible : Visibility.Collapsed;
            faceSet.Visibility = face == "settings" ? Visibility.Visible : Visibility.Collapsed;
            canvas.Selected = sel;
            canvas.InvalidateVisual();
            if (face == "zone") SyncZoneFace();
            if (face == "settings") SyncSettingsFace();
        }

        void SyncZoneFace()
        {
            if (current == null || sel == null) return;
            MonitorInfo m = MonitorOf(sel);
            string mName = m != null ? m.Name : "this monitor";
            int n = current.Zones.IndexOf(sel) + 1;
            zChipText.Text = n.ToString(CultureInfo.InvariantCulture);
            zTitleText.Text = "Zone " + n;
            zOnText.Text = "on " + mName + (m != null && !m.Online ? ", disconnected" : "");

            syncing = true;
            zPicker.Items.Clear();
            zPicker.Items.Add("None, leave it empty");
            int pick = 0;
            for (int i = 0; i < library.Count; i++)
            {
                zPicker.Items.Add(library[i].Name);
                if (string.Equals(library[i].Name, sel.Prog, StringComparison.OrdinalIgnoreCase)) pick = i + 1;
            }
            zPicker.SelectedIndex = pick;
            bool newZone = sel != shownZone;
            shownZone = sel;
            foreach (Field f in new[] { fLeft, fTop, fWidth, fHeight })
                if (newZone || !f.IsKeyboardFocusWithin) f.Text = Pct(Value(KeyOf(f)));
            syncing = false;

            SyncPath();
            SyncFault();

            int onMonitor = m == null ? 1 : current.Zones.Count(z => Monitors.Holds(m, z));
            bool canDelete = onMonitor > 1;
            bDelete.IsEnabled = mDelete.IsEnabled = canDelete;
            string why = canDelete ? "Delete zone" : "A monitor keeps at least one zone. Use Reset monitor.";
            bDelete.ToolTip = canDelete ? null : why;
            mDelete.ToolTip = why;
            bSplitV.IsEnabled = mSplitV.IsEnabled = sel.W >= 2;
            bSplitH.IsEnabled = mSplitH.IsEnabled = sel.H >= 2;
            zLayoutLbl.Text = (mName + " layout").ToUpperInvariant();
            SyncPresets();
        }

        void SyncPresets()
        {
            MonitorInfo m = MonitorOf(sel);
            int match = m == null ? -1 : MatchPreset(m);
            for (int i = 0; i < presetButtons.Count; i++) presetButtons[i].Tag = i == match ? "on" : null;
            zNow.Text = "Now: " + (match >= 0 ? PresetNames[match] : "custom");
        }

        void SyncPath()
        {
            zPath.Inlines.Clear();
            ProgItem p = FindProgram(sel.Prog);
            if (p == null)
            {
                zPath.Inlines.Add(new Run(string.IsNullOrEmpty(sel.Prog)
                    ? "Stays empty. Still a drop target: drag any window here and it snaps to this zone."
                    : sel.Prog + " is not in Programs any more, so nothing launches here."));
                return;
            }
            // A zero-width space after each separator lets the path wrap after a backslash rather
            // than before one, so no line starts with "\".
            zPath.Inlines.Add(new Run(string.IsNullOrEmpty(p.Exe) ? "No executable chosen yet." : p.Exe.Replace("\\", "\\\u200B").Replace("/", "/\u200B")));
            if (!string.IsNullOrEmpty(p.Args))
            {
                zPath.Inlines.Add(new LineBreak());
                zPath.Inlines.Add(Ui.Run("Arguments: " + p.Args, "B.Ink3", FontWeights.Normal));
            }
        }

        void SyncFault()
        {
            string f = sel == null ? null : ZoneFault(sel);
            fLeft.Faulted = f == "origin" && sel.X < 0;
            fTop.Faulted = f == "origin" && sel.Y < 0;
            fWidth.Faulted = f == "right" || (f == "size" && sel.W <= 0);
            fHeight.Faulted = f == "bottom" || (f == "size" && sel.H <= 0);
            zFault.Visibility = f == null ? Visibility.Collapsed : Visibility.Visible;
            zFaultText.Inlines.Clear();
            if (f == null) return;
            MonitorInfo m = MonitorOf(sel);
            int n = current.Zones.IndexOf(sel) + 1;
            if (f == "right" || f == "bottom")
            {
                bool right = f == "right";
                string field = right ? "Width" : "Height", from = right ? "Left" : "Top";
                double start = right ? sel.X : sel.Y;
                zFaultText.Inlines.Add(Ui.Run(field + " takes zone " + n + " past the " + f + " edge of " + (m != null ? m.Name : "its monitor") + ".", "B.Error", FontWeights.Bold));
                zFaultText.Inlines.Add(new Run(" From " + from + " " + Pct(start) + "%, the most it can be is " + Pct(100 - start) + "%. "));
                Hyperlink fit = new Hyperlink(new Run("Fit\u00A0to\u00A0the\u00A0edge")) { Foreground = Ui.B("B.Ink2") };
                fit.Click += delegate { Fit(); };
                fit.MouseEnter += delegate { fit.Foreground = Ui.B("B.Ink"); };
                fit.MouseLeave += delegate { fit.Foreground = Ui.B("B.Ink2"); };
                zFaultText.Inlines.Add(fit);
            }
            else zFaultText.Inlines.Add(Ui.Run(f == "size" ? "Width and Height must be more than 0%." : "Left and Top cannot be below 0%.", "B.Error", FontWeights.Bold));
        }

        void SyncSettingsFace()
        {
            syncing = true;
            startSw.IsChecked = startup;
            hotSw.IsChecked = hotkeyOn;
            syncing = false;
            if (!hotkeyOn) StateLine(hkState, null, "Off. Turn it on to launch the last workspace from anywhere.", false);
            else if (!keptHotkey) StateLine(hkState, null, "Turns on when you save.", false);
            else if (hotkeyReady) StateLine(hkState, "G.Check", "Ready. Launches the last workspace from anywhere.", false);
            else StateLine(hkState, "G.Warn", "Unavailable: another app holds it. Close that app, then save again.", true);
            if (elevated) StateLine(elevState, "G.Check", "Elevated, so admin windows snap too.", false);
            else StateLine(elevState, "G.Warn", "Not elevated. Admin windows will not snap until Slotter runs as administrator.", true);
        }

        static void StateLine(DockPanel host, string icon, string text, bool bad)
        {
            host.Children.Clear();
            string brush = bad ? "B.Error" : "B.Ink2";
            if (icon != null)
            {
                Path p = Ui.Icon(icon, 12, false, Ui.B(brush), icon == "G.Check" ? 1.8 : 1.4);
                p.VerticalAlignment = VerticalAlignment.Top;
                p.Margin = new Thickness(0, 2, 5, 0);
                DockPanel.SetDock(p, Dock.Left);
                host.Children.Add(p);
            }
            TextBlock t = Ui.Text(text, 12, FontWeights.SemiBold, brush);
            t.TextWrapping = TextWrapping.Wrap;
            host.Children.Add(t);
        }

        void RenderCommit()
        {
            commit.Children.Clear();
            bool narrow = mode == Mode.Narrow;
            List<Problem> problems = Problems();
            if (problems.Count > 0)
            {
                string t = narrow ? problems.Count + " to fix" : problems.Count + (problems.Count == 1 ? " problem stops saving" : " problems stop saving");
                Button status = Ui.Button("Btn.Status", Ui.Row(7, Ui.Icon("G.Warn", 12, false), new TextBlock { Text = t, VerticalAlignment = VerticalAlignment.Center }), GotoProblem, "problems");
                status.Margin = new Thickness(0, 0, 4, 0);
                status.ToolTip = "Go to the first problem";
                commit.Children.Add(status);
            }
            else if (dirty)
            {
                StackPanel s = Ui.Row(7, new Ellipse { Width = 8, Height = 8, Fill = Ui.B("B.Ink") }, Ui.Text(narrow ? "Unsaved" : "Unsaved changes", 12, FontWeights.Normal, "B.Ink2"));
                s.Margin = new Thickness(6, 0, 10, 0);
                s.VerticalAlignment = VerticalAlignment.Center;
                commit.Children.Add(s);
            }
            else
            {
                string t = justSaved ? "Saved" : narrow ? "" : "No changes";
                if (t.Length > 0)
                {
                    TextBlock s = Ui.Text(t, 12, FontWeights.Normal, "B.Ink2");
                    s.Margin = new Thickness(6, 0, 10, 0);
                    commit.Children.Add(s);
                }
            }
            Button cancel = Ui.Button("Btn.Quiet", "Cancel", Revert, "cancel");
            cancel.IsEnabled = dirty;
            Button save = Ui.Button("Btn.Primary", narrow ? "Save" : "Save changes", Save, "save");
            save.Margin = new Thickness(8, 0, 0, 0);
            save.Tag = !dirty || problems.Count > 0 ? "blocked" : null;
            if (problems.Count > 0)
                AutomationProperties.SetHelpText(save, "Save is blocked: " + string.Join("; ", problems.Select(p => p.Text)));
            commit.Children.Add(cancel);
            commit.Children.Add(save);
        }

        // ------------------------------------------------------------------ sheet

        void OpenSheet(ProgItem select)
        {
            sheetOpen = true;
            progSel = select ?? (library.Contains(progSel) ? progSel : library.FirstOrDefault());
            scrim.Visibility = Visibility.Visible;
            SizeSheet();
            RenderSheet();
        }

        // A program name still invalid stays pending, so it keeps blocking Save and the problem
        // jump reopens the sheet on it; the live renames typed on the way to it are not kept silently.
        void CloseSheet()
        {
            sheetOpen = false;
            scrim.Visibility = Visibility.Collapsed;
            RenderAll();
        }

        void RenderSheet()
        {
            RenderSheetList();
            bool has = progSel != null;
            formFields.Visibility = has ? Visibility.Visible : Visibility.Collapsed;
            noPrograms.Visibility = has ? Visibility.Collapsed : Visibility.Visible;
            progRemove.IsEnabled = has;
            if (!has) return;
            syncing = true;
            string pending;
            pfName.Text = pendingNames.TryGetValue(progSel, out pending) ? pending : progSel.Name;
            pfPath.Text = progSel.Exe ?? "";
            pfArgs.Text = progSel.Args ?? "";
            syncing = false;
            SyncProgramErrors();
            usedBy.Children.Clear();
            foreach (Profile ws in work)
                for (int i = 0; i < ws.Zones.Count; i++)
                    if (string.Equals(ws.Zones[i].Prog, progSel.Name, StringComparison.OrdinalIgnoreCase))
                    {
                        Border chip = new Border
                        {
                            BorderBrush = Ui.B("B.FieldBorder"), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(3),
                            Padding = new Thickness(8, 3, 8, 3), Margin = new Thickness(0, 0, 6, 6),
                            Child = Ui.Text(ws.Name + " · zone " + (i + 1), 12, FontWeights.Normal, "B.Ink2")
                        };
                        usedBy.Children.Add(chip);
                    }
            usedNone.Visibility = usedBy.Children.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        }

        void RenderSheetList()
        {
            bool narrow = mode == Mode.Narrow;
            Panel list = narrow ? (Panel)new WrapPanel() : new StackPanel();
            foreach (ProgItem p in library)
            {
                ProgItem captured = p;
                int uses = work.Sum(ws => ws.Zones.Count(z => string.Equals(z.Prog, p.Name, StringComparison.OrdinalIgnoreCase)));
                UIElement content;
                TextBlock name = Ui.Text(p.Name, 14, FontWeights.SemiBold, null);
                name.TextTrimming = TextTrimming.CharacterEllipsis;
                if (narrow) content = name;
                else
                {
                    DockPanel row = new DockPanel();
                    TextBlock count = Ui.Text(uses == 0 ? "unused" : uses == 1 ? "1 zone" : uses + " zones", 11, FontWeights.Normal, "B.Ink3");
                    count.Margin = new Thickness(8, 0, 0, 0);
                    DockPanel.SetDock(count, Dock.Right);
                    row.Children.Add(count);
                    row.Children.Add(name);
                    content = row;
                }
                Button b = Ui.Button("ListItem", content, delegate { progSel = captured; RenderSheet(); }, "prog-" + p.Name);
                b.Tag = p == progSel ? "on" : null;
                if (p == progSel) name.FontWeight = FontWeights.ExtraBold;
                AutomationProperties.SetName(b, p.Name);
                if (narrow) { b.Padding = new Thickness(10, 6, 10, 6); b.Margin = new Thickness(0, 0, 4, 4); }
                list.Children.Add(b);
            }
            sheetList.Content = list;
        }

        void SyncProgramErrors()
        {
            if (progSel == null) return;
            string nameErr = ProgramNameError(pfName.Text, progSel);
            pfName.Faulted = nameErr != null;
            pfNameErr.Text = nameErr ?? "";
            pfNameErr.Visibility = nameErr == null ? Visibility.Collapsed : Visibility.Visible;
            bool noPath = string.IsNullOrWhiteSpace(progSel.Exe);
            pfPath.Faulted = noPath;
            pfPathErr.Text = noPath ? "Choose a program or shortcut." : "";
            pfPathErr.Visibility = noPath ? Visibility.Visible : Visibility.Collapsed;
            RenderCommit();
        }

        void OnProgramName()
        {
            if (syncing || progSel == null) return;
            string text = pfName.Text;
            if (ProgramNameError(text, progSel) == null)
            {
                string name = text.Trim();
                if (name != progSel.Name)
                {
                    foreach (Profile ws in work)
                        foreach (Zone z in ws.Zones)
                            if (string.Equals(z.Prog, progSel.Name, StringComparison.OrdinalIgnoreCase)) z.Prog = name;
                    progSel.Name = name;
                }
                pendingNames.Remove(progSel);
            }
            else pendingNames[progSel] = text;
            dirty = true;
            justSaved = false;
            RenderSheetList();
            SyncProgramErrors();
            canvas.Refresh();
        }

        void AddProgram()
        {
            int k = 1;
            string name = "New program";
            while (library.Any(p => string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase))) name = "New program " + (++k);
            ProgItem item = new ProgItem { Name = name, Exe = "", Args = "" };
            library.Add(item);
            progSel = item;
            Touch();
            RenderSheet();
            Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(delegate { pfName.Focus(); pfName.SelectAll(); }));
        }

        void RemoveProgram()
        {
            if (progSel == null) return;
            foreach (Profile ws in work)
                foreach (Zone z in ws.Zones)
                    if (string.Equals(z.Prog, progSel.Name, StringComparison.OrdinalIgnoreCase)) z.Prog = null;
            pendingNames.Remove(progSel);
            library.Remove(progSel);
            progSel = library.FirstOrDefault();
            Touch();
            RenderSheet();
            canvas.Refresh();
        }

        void Browse()
        {
            OpenFileDialog ofd = new OpenFileDialog { Filter = "Programs (*.exe;*.lnk)|*.exe;*.lnk|All files (*.*)|*.*" };
            if (ofd.ShowDialog(this) == true) pfPath.Text = ofd.FileName;
        }

        // ------------------------------------------------------------------ actions

        void SelectWorkspace(Profile ws)
        {
            if (renaming != null && renaming != ws) CommitRename(false);
            current = ws;
            sel = ws.Zones.FirstOrDefault();
            if (face != "settings") face = "zone";
            RenderAll();
        }

        void StartRename()
        {
            if (current == null) return;
            renaming = current;
            renameText = current.Name;
            RenderBar();
            RenderCommit();
            FocusRename();
        }

        void FocusRename()
        {
            Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(delegate
            {
                if (renameBox == null) return;
                renameBox.Focus();
                renameBox.SelectAll();
            }));
        }

        // A valid rename is kept; an invalid one stays open, counted as a problem, when leaving it
        // quietly. Enter on an invalid name does nothing, and the field says why.
        void CommitRename(bool render)
        {
            if (renaming == null || NameError(renameText, renaming) != null) return;
            string name = renameText.Trim();
            if (name != renaming.Name)
            {
                if (string.Equals(activeName, renaming.Name, StringComparison.OrdinalIgnoreCase)) activeName = name;
                renaming.Name = name;
                dirty = true;
                justSaved = false;
            }
            renaming = null;
            if (render) RenderAll();
        }

        void AddWorkspace()
        {
            if (renaming != null) CommitRename(false);
            int k = 1;
            string name;
            do { name = "Workspace " + k++; } while (work.Any(p => string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase)));
            Profile ws = new Profile { Name = name };
            foreach (MonitorInfo m in monitors.Where(x => x.Online))
                ws.Zones.Add(new Zone { Mon = m.Ordinal, MonKey = m.Key, X = 0, Y = 0, W = 100, H = 100 });
            Renumber(ws);
            work.Add(ws);
            current = ws;
            sel = ws.Zones.FirstOrDefault();
            face = "zone";
            renaming = ws;
            renameText = name;
            if (sheetOpen) { sheetOpen = false; scrim.Visibility = Visibility.Collapsed; }
            Touch();
            RenderAll();
            FocusRename();
        }

        void RemoveWorkspace()
        {
            if (current == null) return;
            if (renaming == current) renaming = null;
            bool wasActive = string.Equals(activeName, current.Name, StringComparison.OrdinalIgnoreCase);
            work.Remove(current);
            current = work.FirstOrDefault();
            if (wasActive) activeName = current != null ? current.Name : "";
            sel = current != null ? current.Zones.FirstOrDefault() : null;
            if (current == null) face = null;
            Touch();
            RenderAll();
        }

        void StopUsing(MonitorInfo m)
        {
            current.Zones.RemoveAll(z => Monitors.Holds(m, z));
            Renumber(current);
            sel = current.Zones.FirstOrDefault();
            Touch();
            RenderAll();
        }

        void UseMonitor(MonitorInfo m)
        {
            if (current == null) return;
            Zone z = new Zone { Mon = m.Ordinal, MonKey = m.Key, X = 0, Y = 0, W = 100, H = 100 };
            current.Zones.Add(z);
            Renumber(current);
            sel = z;
            face = "zone";
            Touch();
            RenderAll();
        }

        void OpenWorkspaceMenu(Button anchor)
        {
            if (current == null) return;
            ContextMenu menu = new ContextMenu { Style = Ui.S("Menu"), PlacementTarget = anchor, Placement = PlacementMode.Bottom };
            menu.Items.Add(MenuItemFor("Rename workspace", StartRename));
            menu.Items.Add(MenuItemFor("Remove workspace", RemoveWorkspace));
            AddStopUsing(menu);
            menu.IsOpen = true;
        }

        void OpenSwitcherMenu(Button anchor)
        {
            ContextMenu menu = new ContextMenu { Style = Ui.S("Menu"), PlacementTarget = anchor, Placement = PlacementMode.Bottom };
            foreach (Group g in Groups())
            {
                menu.Items.Add(Tray.Caption(g.Label + (g.AllOff ? " · disconnected" : "")));
                foreach (Profile ws in g.Items)
                {
                    Profile captured = ws;
                    MenuItem item = MenuItemFor(ws.Name + (AllOffline(ws) ? "  (offline)" : ""), delegate { SelectWorkspace(captured); });
                    if (ws == current) item.Tag = "current";
                    menu.Items.Add(item);
                }
            }
            if (menu.Items.Count > 0) menu.Items.Add(Tray.Rule());
            menu.Items.Add(MenuItemFor("New workspace", AddWorkspace));
            if (current != null)
            {
                menu.Items.Add(MenuItemFor("Rename " + current.Name, StartRename));
                menu.Items.Add(MenuItemFor("Remove " + current.Name, RemoveWorkspace));
                AddStopUsing(menu);
            }
            menu.IsOpen = true;
        }

        void AddStopUsing(ContextMenu menu)
        {
            List<MonitorInfo> used = MonitorsOf(current);
            MonitorInfo m = sel != null ? MonitorOf(sel) : null;
            if (m == null || used.Count < 2) return;
            MonitorInfo captured = m;
            menu.Items.Add(MenuItemFor("Stop using " + m.Name + " in " + current.Name, delegate { StopUsing(captured); }));
        }

        static MenuItem MenuItemFor(string text, Action click)
        {
            MenuItem item = new MenuItem { Header = text, Style = Ui.S("Menu.Item") };
            item.Click += delegate { click(); };
            return item;
        }

        void OnPick()
        {
            if (syncing || sel == null) return;
            int i = zPicker.SelectedIndex;
            sel.Prog = i <= 0 || i > library.Count ? null : library[i - 1].Name;
            Touch();
            canvas.Refresh();
            SyncPath();
            RenderHead();
        }

        void OnPosition(Field f, char key)
        {
            if (syncing || sel == null) return;
            double v;
            string text = f.Text.Trim().TrimEnd('%').Trim();
            if (!double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out v) || double.IsNaN(v) || double.IsInfinity(v)) return;
            // A field shows a rounded value; typing back what it already shows must not round the
            // stored one (three 33.33/33.34 columns would all become 33.3).
            if (Pct(v) == Pct(Value(key))) return;
            switch (key)
            {
                case 'x': sel.X = v; break;
                case 'y': sel.Y = v; break;
                case 'w': sel.W = v; break;
                default: sel.H = v; break;
            }
            Touch();
            canvas.Refresh();
            SyncFault();
            SyncPresets();
            bSplitV.IsEnabled = mSplitV.IsEnabled = sel.W >= 2;
            bSplitH.IsEnabled = mSplitH.IsEnabled = sel.H >= 2;
        }

        double Value(char key) { return key == 'x' ? sel.X : key == 'y' ? sel.Y : key == 'w' ? sel.W : sel.H; }
        char KeyOf(Field f) { return f == fLeft ? 'x' : f == fTop ? 'y' : f == fWidth ? 'w' : 'h'; }

        void Fit()
        {
            if (sel == null) return;
            if (sel.X + sel.W > 100) sel.W = 100 - sel.X;
            if (sel.Y + sel.H > 100) sel.H = 100 - sel.Y;
            Touch();
            canvas.Refresh();
            SyncZoneFace();
        }

        void Split(bool vertical)
        {
            if (current == null || sel == null) return;
            Zone z = sel;
            if ((vertical && z.W < 2) || (!vertical && z.H < 2)) return;
            Zone added = new Zone { Mon = z.Mon, MonKey = z.MonKey, X = z.X, Y = z.Y, W = z.W, H = z.H };
            if (vertical) { double half = z.W / 2; added.X = z.X + half; added.W = z.W - half; z.W = half; }
            else { double half = z.H / 2; added.Y = z.Y + half; added.H = z.H - half; z.H = half; }
            current.Zones.Insert(current.Zones.IndexOf(z) + 1, added);
            Renumber(current);
            sel = added;
            face = "zone";
            Structural();
        }

        void DeleteZone()
        {
            if (current == null || sel == null) return;
            MonitorInfo m = MonitorOf(sel);
            if (m != null && current.Zones.Count(z => Monitors.Holds(m, z)) < 2) return;
            current.Zones.Remove(sel);
            Renumber(current);
            sel = m != null ? current.Zones.FirstOrDefault(z => Monitors.Holds(m, z)) : current.Zones.FirstOrDefault();
            Structural();
        }

        void ResetMonitor()
        {
            if (current == null || sel == null) return;
            MonitorInfo m = MonitorOf(sel);
            if (m == null) return;
            List<Zone> old = current.Zones.Where(z => Monitors.Holds(m, z)).ToList();
            Zone keep = old.FirstOrDefault(z => !string.IsNullOrEmpty(z.Prog));
            current.Zones.RemoveAll(z => Monitors.Holds(m, z));
            Zone full = new Zone { Mon = old[0].Mon, MonKey = m.Key, X = 0, Y = 0, W = 100, H = 100, Prog = keep != null ? keep.Prog : null };
            current.Zones.Add(full);
            Renumber(current);
            sel = full;
            Structural();
        }

        void ApplyPreset(int index)
        {
            if (current == null || sel == null) return;
            MonitorInfo m = MonitorOf(sel);
            if (m == null) return;
            List<Zone> old = current.Zones.Where(z => Monitors.Holds(m, z)).ToList();
            int mon = old.Count > 0 ? old[0].Mon : m.Ordinal;
            current.Zones.RemoveAll(z => Monitors.Holds(m, z));
            Zone first = null;
            for (int i = 0; i < PresetSets[index].Length; i++)
            {
                double[] r = PresetSets[index][i];
                Zone z = new Zone { Mon = mon, MonKey = m.Key, X = r[0], Y = r[1], W = r[2], H = r[3], Prog = i < old.Count ? old[i].Prog : null };
                current.Zones.Add(z);
                if (first == null) first = z;
            }
            Renumber(current);
            sel = first;
            Structural();
        }

        void Structural()
        {
            Touch();
            canvas.Profile = current;
            canvas.Selected = sel;
            canvas.Refresh();
            RenderDrawer();
            RenderHead();
        }

        void Touch()
        {
            dirty = true;
            justSaved = false;
            RenderCommit();
        }

        void GotoProblem()
        {
            List<Problem> problems = Problems();
            if (problems.Count == 0) return;
            Problem p = problems[0];
            if (p.Name) { FocusRename(); return; }
            if (p.Prog != null)
            {
                OpenSheet(p.Prog);
                Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(delegate { (pfName.Faulted ? pfName : pfPath).Focus(); }));
                return;
            }
            if (sheetOpen) CloseSheet();
            current = p.Ws;
            sel = p.Zone;
            face = "zone";
            RenderAll();
            Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(delegate
            {
                Field bad = new[] { fWidth, fHeight, fLeft, fTop }.FirstOrDefault(f => f.Faulted) ?? fWidth;
                bad.Focus();
                bad.SelectAll();
            }));
        }

        void Save()
        {
            if (Problems().Count > 0) { GotoProblem(); return; }
            CommitRename(false);
            if (!dirty) return;
            FinalizeSave();
            if (current != null) activeName = current.Name;
            else if (Config.FindProfile(work, activeName) == null) activeName = work.Count > 0 ? work[0].Name : "";
            Func<List<Profile>, List<ProgItem>, string, bool, bool, bool> handler = Saved;
            // A write that failed keeps the edits staged, so Save can be tried again.
            if (handler != null && !handler(CloneProfiles(work), CloneLibrary(library), activeName, startup, hotkeyOn)) { RenderAll(); return; }
            Keep();
            dirty = false;
            justSaved = true;
            RenderAll();
        }

        void Revert()
        {
            string keepName = current != null ? current.Name : null;
            work = CloneProfiles(keptWork);
            library = CloneLibrary(keptLibrary);
            startup = keptStartup;
            hotkeyOn = keptHotkey;
            activeName = keptActive;
            renaming = null;
            pendingNames.Clear();
            progSel = null;
            current = Config.FindProfile(work, keepName ?? "") ?? work.FirstOrDefault();
            sel = current != null ? current.Zones.FirstOrDefault() : null;
            dirty = false;
            justSaved = false;
            if (sheetOpen) progSel = library.FirstOrDefault();
            RenderAll();
        }

        void Keep()
        {
            keptWork = CloneProfiles(work);
            keptLibrary = CloneLibrary(library);
            keptStartup = startup;
            keptHotkey = hotkeyOn;
            keptActive = activeName;
        }

        // Carried over from the old designer: every zone gets its monitor's resolution key and a
        // clean sequential name before App writes profiles.ini.
        void FinalizeSave()
        {
            System.Windows.Forms.Screen[] screens = System.Windows.Forms.Screen.AllScreens;
            foreach (Profile p in work)
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
        }

        void OnKey(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Escape && sheetOpen) { CloseSheet(); e.Handled = true; }
        }

        void OnClosing(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (closingApproved || !dirty) return;
            if (Confirm.Ask(this, "Discard unsaved changes?", "Your workspace, program and app setting changes have not been saved.", "Discard changes", true)) closingApproved = true;
            else e.Cancel = true;
        }

        // ------------------------------------------------------------------ rules

        List<Problem> Problems()
        {
            List<Problem> list = new List<Problem>();
            if (renaming != null)
            {
                string e = NameError(renameText, renaming);
                if (e != null) list.Add(new Problem { Ws = renaming, Name = true, Text = e });
            }
            foreach (Profile ws in work)
                for (int i = 0; i < ws.Zones.Count; i++)
                {
                    string f = ZoneFault(ws.Zones[i]);
                    if (f != null) list.Add(new Problem { Ws = ws, Zone = ws.Zones[i], Text = ws.Name + ", zone " + (i + 1) + ": " + CanvasFault(ws.Zones[i]) });
                }
            foreach (ProgItem p in library)
            {
                string pending;
                string e = pendingNames.TryGetValue(p, out pending) ? ProgramNameError(pending, p) : null;
                if (e == null && string.IsNullOrWhiteSpace(p.Exe)) e = p.Name + " has no executable.";
                if (e != null) list.Add(new Problem { Prog = p, Text = e });
            }
            return list;
        }

        static string ZoneFault(Zone z)
        {
            if (z.W <= 0 || z.H <= 0) return "size";
            if (z.X < 0 || z.Y < 0) return "origin";
            if (z.X + z.W > 100.05) return "right";
            if (z.Y + z.H > 100.05) return "bottom";
            return null;
        }

        static string CanvasFault(Zone z)
        {
            switch (ZoneFault(z))
            {
                case null: return null;
                case "right": return "Runs " + Pct(z.X + z.W - 100) + "% past the right edge";
                case "bottom": return "Runs " + Pct(z.Y + z.H - 100) + "% past the bottom edge";
                case "size": return "Width and Height must be more than 0%";
                default: return "Left and Top cannot be below 0%";
            }
        }

        string NameError(string raw, Profile self)
        {
            string name = (raw ?? "").Trim();
            if (name.Length == 0) return "Give the workspace a name.";
            if (name.Length > 48) return "Use 48 characters or fewer.";
            if (name.IndexOfAny(new[] { '[', ']', '=', ',' }) >= 0) return "Names cannot contain [ ] = ,";
            foreach (string reserved in new[] { "Profiles", "Programs", "Panel", "Settings", "Displays" })
                if (string.Equals(name, reserved, StringComparison.OrdinalIgnoreCase)) return "That name is reserved by Slotter.";
            foreach (Profile p in work)
                if (p != self && string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase)) return "A workspace with that name already exists.";
            return null;
        }

        string ProgramNameError(string raw, ProgItem self)
        {
            string name = (raw ?? "").Trim();
            if (name.Length == 0) return "Give the program a name.";
            if (name.Length > 64) return "Use 64 characters or fewer.";
            foreach (ProgItem p in library)
                if (p != self && string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase)) return "A program with that name already exists.";
            return null;
        }

        // ------------------------------------------------------------------ queries

        MonitorInfo MonitorOf(Zone z) { return z == null ? null : Monitors.Find(monitors, z); }

        List<MonitorInfo> MonitorsOf(Profile ws)
        {
            return monitors.Where(m => ws.Zones.Any(z => Monitors.Holds(m, z))).ToList();
        }

        bool AllOffline(Profile ws)
        {
            List<MonitorInfo> used = MonitorsOf(ws);
            return used.Count > 0 && used.All(m => !m.Online);
        }

        List<Group> Groups()
        {
            List<Group> groups = new List<Group>();
            foreach (Profile ws in work)
            {
                List<MonitorInfo> used = MonitorsOf(ws);
                string key = string.Join("+", used.Select(m => m.Key));
                Group g = groups.FirstOrDefault(x => string.Join("+", x.Mons.Select(m => m.Key)) == key);
                if (g == null)
                {
                    g = new Group { Mons = used, Label = used.Count == 0 ? "No monitors" : GroupLabel(used), AllOff = used.Count > 0 && used.All(m => !m.Online) };
                    groups.Add(g);
                }
                g.Items.Add(ws);
            }
            return groups;
        }

        static string GroupLabel(List<MonitorInfo> used) { return string.Join(" + ", used.Select(m => m.Name)); }

        FrameworkElement Pictogram(List<MonitorInfo> used)
        {
            DeskLayout d = DeskLayout.For(monitors);
            double bottom = d.Pieces.Count == 0 ? 1 : d.Pieces.Max(p => p.Y + p.H);
            double s = Math.Min(22 / d.Width, 11 / bottom);
            Canvas c = new Canvas { Width = Math.Ceiling(d.Width * s) + 1, Height = Math.Ceiling(bottom * s) + 1, VerticalAlignment = VerticalAlignment.Center, SnapsToDevicePixels = true };
            foreach (DeskLayout.Piece p in d.Pieces)
            {
                Rectangle r = new Rectangle
                {
                    Width = Math.Max(3, Math.Round(p.W * s)), Height = Math.Max(2, Math.Round(p.H * s)), RadiusX = 1, RadiusY = 1,
                    Stroke = Ui.B("B.Ink3"), StrokeThickness = 1, Fill = used.Contains(p.Monitor) ? Ui.B("B.Ink3") : null
                };
                Canvas.SetLeft(r, Math.Round((p.X - DeskLayout.Bezel) * s));
                Canvas.SetTop(r, Math.Round(p.Y * s));
                c.Children.Add(r);
            }
            return c;
        }

        int MatchPreset(MonitorInfo m)
        {
            List<Zone> zs = current.Zones.Where(z => Monitors.Holds(m, z)).ToList();
            for (int i = 0; i < PresetSets.Length; i++)
            {
                double[][] set = PresetSets[i];
                if (set.Length != zs.Count) continue;
                if (set.All(q => zs.Any(z => Math.Abs(z.X - q[0]) < 0.2 && Math.Abs(z.Y - q[1]) < 0.2 && Math.Abs(z.W - q[2]) < 0.2 && Math.Abs(z.H - q[3]) < 0.2))) return i;
            }
            return -1;
        }

        // Zones are numbered left to right, monitor by monitor, then top to bottom and left to
        // right within a monitor, so the numbers read in the order the desk does.
        void Renumber(Profile p)
        {
            List<Zone> sorted = p.Zones
                .OrderBy(z => { int i = monitors.FindIndex(m => Monitors.Holds(m, z)); return i < 0 ? int.MaxValue : i; })
                .ThenBy(z => Math.Round(z.Y, 2)).ThenBy(z => Math.Round(z.X, 2)).ToList();
            p.Zones.Clear();
            p.Zones.AddRange(sorted);
            for (int i = 0; i < p.Zones.Count; i++) p.Zones[i].Name = "Zone" + (i + 1);
        }

        ProgItem FindProgram(string name)
        {
            if (string.IsNullOrEmpty(name)) return null;
            return library.FirstOrDefault(p => string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase));
        }

        static List<Profile> CloneProfiles(IEnumerable<Profile> list) { return list.Select(p => p.Clone()).ToList(); }
        static List<ProgItem> CloneLibrary(IEnumerable<ProgItem> list) { return list.Select(p => new ProgItem { Name = p.Name, Exe = p.Exe, Args = p.Args }).ToList(); }

        // One decimal, trailing zeros trimmed, for every percentage shown: fields and sentences alike.
        // Storage keeps full precision.
        static string Pct(double v) { return Math.Round(v, 1).ToString("0.#", CultureInfo.InvariantCulture); }

        static string CountWords(int n)
        {
            string[] words = { "No", "One", "Two", "Three", "Four", "Five", "Six" };
            return (n < words.Length ? words[n] : n.ToString(CultureInfo.InvariantCulture)) + (n == 1 ? " monitor" : " monitors");
        }

        static string Names(List<MonitorInfo> list) { return JoinAnd(list.Select(m => m.Name).ToList()); }

        static string JoinAnd(List<string> parts)
        {
            if (parts.Count == 0) return "";
            if (parts.Count == 1) return parts[0];
            return string.Join(", ", parts.Take(parts.Count - 1)) + " and " + parts[parts.Count - 1];
        }
    }
}
