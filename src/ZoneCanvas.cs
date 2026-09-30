using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Input;
using System.Windows.Media;
using Ykit;
using Forms = System.Windows.Forms;

namespace Snappy
{
    // The spatial canvas: monitors laid out as they sit on the desk, with each
    // workspace's zones drawn inside them. This is Snappy's own version of the "the
    // monitors on the desk are the interface" idea the design system calls out, so it
    // stays a custom-drawn diagram rather than a grid of controls -- the same
    // exception AspectBox already makes. Every dimension here is computed from
    // ActualWidth/ActualHeight on each render, never a pixel measured once, so it is
    // correct at any DPI and any window size with no manual scaling.
    public class ZoneCanvas : FrameworkElement
    {
        public Profile Profile;
        public Zone Selected;
        public int SelectedMon = 1;
        public event EventHandler SelectionChanged;

        Rect[] monRects = new Rect[0];
        string[] monKeys = new string[0];

        public ZoneCanvas()
        {
            Focusable = true;
            SnapsToDevicePixels = true;
            AutomationProperties.SetName(this, "Monitor and zone canvas");
            AutomationProperties.SetHelpText(this, "Use arrow keys to move between zones and Page Up or Page Down to change monitors.");
        }

        void DesignableMonitors(out Rectangle2[] work, out bool[] offline, out string[] keys)
        {
            Forms.Screen[] screens = Forms.Screen.AllScreens;
            int connected = screens.Length;
            List<string> disconnectedKeys = new List<string>();
            if (Profile != null)
                foreach (Zone z in Profile.Zones)
                    if (!string.IsNullOrEmpty(z.MonKey) && Config.ResolveScreenIndex(z, screens) < 0 && !disconnectedKeys.Contains(z.MonKey))
                        disconnectedKeys.Add(z.MonKey);
            int count = Math.Max(1, connected + disconnectedKeys.Count);
            work = new Rectangle2[count];
            offline = new bool[count];
            keys = new string[count];
            Rectangle2 proto = connected > 0
                ? Rectangle2.FromForms(screens[0].WorkingArea)
                : new Rectangle2(0, 0, 1920, 1080);
            double nextX = proto.Right;
            for (int i = 0; i < connected; i++)
            {
                work[i] = Rectangle2.FromForms(screens[i].WorkingArea);
                keys[i] = screens[i].Bounds.Width + "x" + screens[i].Bounds.Height;
                if (work[i].Right > nextX) nextX = work[i].Right;
            }
            for (int i = connected; i < count; i++)
            {
                work[i] = new Rectangle2(nextX, proto.Top, proto.Width, proto.Height);
                offline[i] = true;
                keys[i] = i - connected < disconnectedKeys.Count ? disconnectedKeys[i - connected] : "";
                nextX += proto.Width;
            }
        }

        public string[] GetMonitorKeys()
        {
            Rectangle2[] work; bool[] offline; string[] keys;
            DesignableMonitors(out work, out offline, out keys);
            return keys;
        }

        void ComputeLayout(Rectangle2[] work)
        {
            monRects = new Rect[work.Length];
            double minX = double.MaxValue, minY = double.MaxValue, maxX = double.MinValue, maxY = double.MinValue;
            foreach (Rectangle2 w in work)
            {
                if (w.Left < minX) minX = w.Left; if (w.Top < minY) minY = w.Top;
                if (w.Right > maxX) maxX = w.Right; if (w.Bottom > maxY) maxY = w.Bottom;
            }
            double vw = Math.Max(1, maxX - minX), vh = Math.Max(1, maxY - minY);
            double pad = 28;
            double width = Math.Max(1, ActualWidth), height = Math.Max(1, ActualHeight);
            double sc = Math.Min((width - 2 * pad) / vw, (height - 2 * pad) / vh);
            if (sc <= 0 || double.IsInfinity(sc)) sc = 0.1;
            double offX = (width - vw * sc) / 2, offY = (height - vh * sc) / 2;
            for (int i = 0; i < work.Length; i++)
            {
                Rectangle2 w = work[i];
                monRects[i] = new Rect(
                    offX + (w.Left - minX) * sc, offY + (w.Top - minY) * sc,
                    Math.Max(1, w.Width * sc), Math.Max(1, w.Height * sc));
            }
        }

        static Rect ZoneRect(Rect m, Zone z)
        {
            return new Rect(
                m.X + z.X / 100.0 * m.Width, m.Y + z.Y / 100.0 * m.Height,
                Math.Max(1, z.W / 100.0 * m.Width), Math.Max(1, z.H / 100.0 * m.Height));
        }

        Brush Token(string key) { return (Brush)TryFindResource(key) ?? Brushes.Magenta; }

        protected override void OnRender(DrawingContext dc)
        {
            base.OnRender(dc);
            Forms.Screen[] screens = Forms.Screen.AllScreens;
            Rectangle2[] work; bool[] offline;
            DesignableMonitors(out work, out offline, out monKeys);
            ComputeLayout(work);

            Brush monBrush = Token("FieldRaisedBrush");
            Brush offBrush = Token("FieldBrush");
            Pen monPen = new Pen(Token("RuleBrush"), 1);
            Pen gridPen = new Pen(Token("RuleBrush"), 1) { Brush = Dim(Token("RuleBrush"), 0.4) };
            Brush dim = Token("InkTertiaryBrush");
            Brush accent = Token("AccentBrush");
            Brush ink = Token("InkBrush");
            Brush accentInk = Token("AccentInkBrush");
            Brush panel = Token("PanelBrush");

            for (int i = 0; i < work.Length; i++)
            {
                Rect r = monRects[i];
                dc.DrawRectangle(offline[i] ? offBrush : monBrush, null, r);
                for (int x = 1; x < 10; x++) dc.DrawLine(gridPen, new Point(r.X + r.Width * x / 10, r.Y), new Point(r.X + r.Width * x / 10, r.Bottom));
                for (int y = 1; y < 10; y++) dc.DrawLine(gridPen, new Point(r.X, r.Y + r.Height * y / 10), new Point(r.Right, r.Y + r.Height * y / 10));
                if (i + 1 == SelectedMon) dc.DrawRectangle(null, new Pen(accent, 2), Rect.Inflate(r, 2, 2));
                dc.DrawRectangle(null, monPen, r);

                Label(dc, Config.MonitorLabel(monKeys[i]), r.X + 8, r.Y + 6, dim, 12, FontWeights.SemiBold);
                string sizeText = offline[i] ? "disconnected" : screens[i].Bounds.Width + " x " + screens[i].Bounds.Height;
                Label(dc, sizeText, r.X + 8, r.Bottom - 22, dim, 11, FontWeights.Normal);

                if (Profile == null) continue;
                int ord = 0;
                foreach (Zone z in Profile.Zones)
                {
                    if (!Config.ZoneInSlot(z, monKeys[i], i + 1)) continue;
                    ord++;
                    Rect zr = ZoneRect(r, z);
                    zr.Inflate(-1, -1);
                    bool selz = z == Selected;
                    bool free = string.IsNullOrEmpty(z.Prog);
                    dc.DrawRectangle(selz ? accent : panel, null, zr);
                    Pen zonePen = new Pen(selz ? ink : Token("RuleBrush"), selz ? 2 : 1);
                    if (free && !selz) zonePen.DashStyle = DashStyles.Dash;
                    dc.DrawRectangle(null, zonePen, zr);
                    if (selz)
                    {
                        dc.DrawRectangle(accent, null, new Rect(zr.X, zr.Bottom - 3, zr.Width, 3));
                        DrawCorners(dc, zr, accent);
                    }
                    string text = "Zone " + ord + (string.IsNullOrEmpty(z.Prog) ? "" : "\n" + z.Prog);
                    LabelCentered(dc, text, zr, selz ? accentInk : ink, 11, FontWeights.SemiBold);
                }
                if (ord == 0)
                {
                    Rect empty = new Rect(r.X + 18, r.Y + 28, Math.Max(1, r.Width - 36), Math.Max(1, r.Height - 56));
                    LabelCentered(dc, "Select this monitor, then choose a preset", empty, dim, 11, FontWeights.Normal);
                }
            }

            if (IsFocused && SelectedMon > 0 && SelectedMon <= monRects.Length)
                dc.DrawRectangle(null, new Pen(ink, 1) { DashStyle = DashStyles.Dot }, Rect.Inflate(monRects[SelectedMon - 1], 5, 5));
        }

        static Brush Dim(Brush b, double opacity)
        {
            Brush clone = (Brush)b.Clone();
            clone.Opacity = opacity;
            clone.Freeze();
            return clone;
        }

        static void DrawCorners(DrawingContext dc, Rect r, Brush brush)
        {
            double length = Math.Max(4, Math.Min(12, Math.Min(r.Width, r.Height) / 4));
            Pen pen = new Pen(brush, 2.5) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
            dc.DrawLine(pen, new Point(r.Left, r.Top), new Point(r.Left + length, r.Top));
            dc.DrawLine(pen, new Point(r.Left, r.Top), new Point(r.Left, r.Top + length));
            dc.DrawLine(pen, new Point(r.Right, r.Top), new Point(r.Right - length, r.Top));
            dc.DrawLine(pen, new Point(r.Right, r.Top), new Point(r.Right, r.Top + length));
            dc.DrawLine(pen, new Point(r.Left, r.Bottom), new Point(r.Left + length, r.Bottom));
            dc.DrawLine(pen, new Point(r.Left, r.Bottom), new Point(r.Left, r.Bottom - length));
            dc.DrawLine(pen, new Point(r.Right, r.Bottom), new Point(r.Right - length, r.Bottom));
            dc.DrawLine(pen, new Point(r.Right, r.Bottom), new Point(r.Right, r.Bottom - length));
        }

        void Label(DrawingContext dc, string text, double x, double y, Brush brush, double size, FontWeight weight)
        {
            FormattedText ft = Formatted(text, brush, size, weight);
            dc.DrawText(ft, new Point(x, y));
        }

        void LabelCentered(DrawingContext dc, string text, Rect bounds, Brush brush, double size, FontWeight weight)
        {
            FormattedText ft = Formatted(text, brush, size, weight);
            ft.MaxTextWidth = Math.Max(1, bounds.Width - 6);
            ft.MaxTextHeight = Math.Max(1, bounds.Height - 4);
            ft.TextAlignment = TextAlignment.Center;
            ft.Trimming = TextTrimming.CharacterEllipsis;
            double x = bounds.X + (bounds.Width - ft.Width) / 2;
            double y = bounds.Y + Math.Max(2, (bounds.Height - ft.Height) / 2);
            dc.DrawText(ft, new Point(bounds.X + 3, y));
        }

        FormattedText Formatted(string text, Brush brush, double size, FontWeight weight)
        {
            return new FormattedText(text, System.Globalization.CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
                new Typeface(new FontFamily("Segoe UI Variable Text, Segoe UI"), FontStyles.Normal, weight, FontStretches.Normal),
                size, brush, VisualTreeHelper.GetDpi(this).PixelsPerDip);
        }

        protected override void OnMouseDown(MouseButtonEventArgs e)
        {
            base.OnMouseDown(e);
            Focus();
            Point p = e.GetPosition(this);
            string[] keys = GetMonitorKeys();
            for (int i = 0; i < monRects.Length; i++)
            {
                if (!monRects[i].Contains(p)) continue;
                SelectedMon = i + 1;
                Zone hit = null;
                if (Profile != null)
                    foreach (Zone z in Profile.Zones)
                        if (Config.ZoneInSlot(z, keys[i], i + 1) && ZoneRect(monRects[i], z).Contains(p)) hit = z; // last drawn wins
                Selected = hit;
                NotifySelection();
                return;
            }
        }

        protected override void OnPreviewKeyDown(KeyEventArgs e)
        {
            base.OnPreviewKeyDown(e);
            string[] keys = GetMonitorKeys();
            if (e.Key == Key.PageUp || e.Key == Key.PageDown)
            {
                int count = monRects.Length;
                if (count == 0) return;
                SelectedMon = ((SelectedMon - 1 + (e.Key == Key.PageDown ? 1 : -1) + count) % count) + 1;
                Selected = Profile == null ? null : Profile.Zones.Find(z => Config.ZoneInSlot(z, keys[SelectedMon - 1], SelectedMon));
                NotifySelection();
                e.Handled = true;
                return;
            }
            if (e.Key != Key.Left && e.Key != Key.Right && e.Key != Key.Up && e.Key != Key.Down) return;
            if (Profile == null || SelectedMon <= 0 || SelectedMon > keys.Length) return;
            List<Zone> zones = Profile.Zones.FindAll(z => Config.ZoneInSlot(z, keys[SelectedMon - 1], SelectedMon));
            if (zones.Count == 0) return;
            int direction = (e.Key == Key.Left || e.Key == Key.Up) ? -1 : 1;
            int index = zones.IndexOf(Selected);
            if (index < 0) index = direction > 0 ? -1 : 0;
            index = (index + direction + zones.Count) % zones.Count;
            Selected = zones[index];
            NotifySelection();
            e.Handled = true;
        }

        void NotifySelection()
        {
            string[] keys = GetMonitorKeys();
            string monLabel = Config.MonitorLabel(SelectedMon > 0 && SelectedMon <= keys.Length ? keys[SelectedMon - 1] : "");
            AutomationProperties.SetName(this, Selected == null ? monLabel + " selected." : monLabel + ", " + Selected.Name + " selected" + (string.IsNullOrEmpty(Selected.Prog) ? "." : ", assigned to " + Selected.Prog + "."));
            InvalidateVisual();
            EventHandler handler = SelectionChanged;
            if (handler != null) handler(this, EventArgs.Empty);
        }

        protected override void OnGotFocus(RoutedEventArgs e) { base.OnGotFocus(e); InvalidateVisual(); }
        protected override void OnLostFocus(RoutedEventArgs e) { base.OnLostFocus(e); InvalidateVisual(); }
    }

    // A double-precision rectangle mirroring System.Drawing.Rectangle's semantics
    // (Right/Bottom are edges, not size), for the monitor-layout maths above.
    struct Rectangle2
    {
        public double Left, Top, Width, Height;
        public Rectangle2(double left, double top, double width, double height) { Left = left; Top = top; Width = width; Height = height; }
        public double Right { get { return Left + Width; } }
        public double Bottom { get { return Top + Height; } }
        public static Rectangle2 FromForms(System.Drawing.Rectangle r) { return new Rectangle2(r.Left, r.Top, r.Width, r.Height); }
    }
}
