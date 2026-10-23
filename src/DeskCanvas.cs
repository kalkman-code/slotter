using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Input;
using System.Windows.Media;

namespace Slotter
{
    // The desk being designed: every monitor drawn as an object on one desk line at its true
    // physical size, with the workspace's zones on its screen. Drawn rather than built from
    // controls, because it is one diagram at one scale factor; every length is recomputed
    // from the element's size on each layout, so it holds at any DPI and window size.
    public sealed class DeskCanvas : FrameworkElement
    {
        public List<MonitorInfo> Monitors = new List<MonitorInfo>();
        public Profile Profile;
        public List<VirtualPlate> VirtualPlates = new List<VirtualPlate>();
        public Zone Selected;
        public List<ProgItem> Library = new List<ProgItem>();
        public bool Narrow;
        public double ReservedHeight;
        public double Scale { get; private set; }
        public Func<Zone, string> Fault = delegate { return null; };
        public Func<string, string> DesktopLabel = delegate { return "Desktop"; };
        public Func<string, int> DesktopOrdinal = delegate { return 0; };
        public Func<VirtualPlate, string> PlateName = plate => plate.Name;
        public Rect GhostBounds { get { return addGhost; } }

        public event Action<Zone> ZoneClicked;
        public event Action Laid;
        public event Action VirtualAddClicked;
        public event Action<VirtualPlate> VirtualSetupClicked;
        public event Action<VirtualPlate> VirtualBenchClicked;
        public event Action<VirtualPlate> VirtualRenameClicked;

        public sealed class Placed
        {
            public MonitorInfo Monitor;
            public Rect Outer, Screen, Neck, Foot;
            public Point Plate;
            public double PlateHalf;
            public bool Used;
            public VirtualPlate VirtualPlate;
        }

        public readonly List<Placed> Placements = new List<Placed>();
        readonly List<KeyValuePair<Zone, Rect>> zoneRects = new List<KeyValuePair<Zone, Rect>>();
        double deskTop;
        Zone hover;
        Rect addGhost;
        double ghostNeckWidth, ghostFootWidth;

        public DeskCanvas()
        {
            Focusable = true;
            FocusVisualStyle = null;
            ClipToBounds = true;
            AutomationProperties.SetName(this, "Desk: monitors and zones");
            AutomationProperties.SetHelpText(this, "Arrow keys move between zones.");
        }

        // The accessible name says what the selected zone launches and, when it has one, its fault.
        void Describe()
        {
            Zone z = Selected;
            string fault = z == null ? null : Fault(z);
            AutomationProperties.SetName(this, z == null ? "Desk" : "Zone " + (IndexOf(z) + 1) + ", " + (string.IsNullOrEmpty(z.Prog) ? "empty" : z.Prog) + ", selected"
                + (fault != null ? ". Problem: " + fault + "." : ""));
        }

        public void Refresh()
        {
            Describe();
            Compute(RenderSize);
            InvalidateVisual();
            if (Laid != null) Laid();
        }

        public Rect VirtualNameBounds(string plateId)
        {
            Placed p = Placements.FirstOrDefault(item => item.VirtualPlate != null && string.Equals(item.VirtualPlate.Id, plateId, StringComparison.OrdinalIgnoreCase));
            return p == null ? Rect.Empty : new Rect(p.Plate.X - p.PlateHalf, p.Plate.Y - 2, p.PlateHalf * 2, 18);
        }

        Rect VirtualBenchBounds(string plateId)
        {
            Placed p = Placements.FirstOrDefault(item => item.VirtualPlate != null && string.Equals(item.VirtualPlate.Id, plateId, StringComparison.OrdinalIgnoreCase));
            if (p == null) return Rect.Empty;
            FormattedText badge = Txt(PlateDesktopLabel(p), 10, FontWeights.SemiBold, B("B.Ink2"), p.Outer.Width - 23);
            double width = badge.Width + 5 + 18;
            return new Rect(p.Plate.X + width / 2 - 18, p.Plate.Y + 14, 18, 17);
        }

        protected override Size ArrangeOverride(Size finalSize)
        {
            Compute(finalSize);
            if (Laid != null) Dispatcher.BeginInvoke(new Action(delegate { if (Laid != null) Laid(); }));
            return finalSize;
        }

        string PlateDesktopLabel(Placed p)
        {
            int ordinal = DesktopOrdinal(p.VirtualPlate.DesktopId);
            return p.Outer.Width < 130 && ordinal > 0 ? "Win " + ordinal : DesktopLabel(p.VirtualPlate.DesktopId);
        }

        void Compute(Size size)
        {
            Placements.Clear();
            zoneRects.Clear();
            double W = Math.Max(1, size.Width), H = Math.Max(1, size.Height);
            DeskLayout d = DeskLayout.For(Monitors);
            List<VirtualPlate> pinned = Profile == null ? new List<VirtualPlate>() : Profile.VirtualPlates.Where(p => !p.Benched)
                .OrderBy(p => DesktopOrdinal(p.DesktopId) > 0 ? DesktopOrdinal(p.DesktopId) : int.MaxValue).ToList();
            double extra = 0;
            foreach (VirtualPlate plate in pinned)
            {
                MonitorInfo monitor = PlateMonitor(plate);
                DeskLayout.Piece piece = d.Pieces.FirstOrDefault(p => monitor != null && p.Monitor.Key == monitor.Key) ?? d.Pieces.LastOrDefault();
                if (piece != null) extra += piece.W + 2 * DeskLayout.Bezel;
            }
            DeskLayout.Piece tail = d.Pieces.FirstOrDefault();
            double ghostW = tail == null ? 0 : tail.W + 2 * DeskLayout.Bezel;
            double totalWidth = d.Width + extra + ghostW + (pinned.Count + 1) * DeskLayout.Gap;
            double capH = Narrow ? 64 : 68, pad = Narrow ? 12 : 32;
            double deskHeight = Math.Max(1, H - ReservedHeight);
            double s = Math.Max(0.1, Math.Min((W - pad * 2) / totalWidth, (deskHeight - capH - 10) / d.DeskY));
            Scale = s;
            double ox = (W - totalWidth * s) / 2;
            double free = deskHeight - capH - d.DeskY * s;
            // Monitors sit a little below centre so the desk reads as a surface; in the narrow
            // first run they drop to the desk line to leave room for the note above them.
            double oy = Math.Max(4, free - Math.Max(0, free * (Profile == null && Narrow ? 0 : 0.35)));
            deskTop = Math.Round(oy + d.DeskY * s);
            double gapPx = DeskLayout.Gap * s;
            double cursorX = ox;

            foreach (DeskLayout.Piece p in d.Pieces)
            {
                double bz = Math.Max(3, DeskLayout.Bezel * s), chin = Math.Max(5, DeskLayout.Chin * s);
                double sw = p.W * s, sh = p.H * s;
                double left = Math.Round(cursorX), top = Math.Round(oy + d.DeskY * s - DeskLayout.Clearance * s - (p.H * s + bz + chin));
                Rect outer = new Rect(left, top, Math.Round(sw + 2 * bz), Math.Round(sh + bz + chin));
                Rect screen = new Rect(Math.Round(left + bz), Math.Round(top + bz), Math.Round(sw), Math.Round(sh));
                double cx = outer.X + outer.Width / 2;
                double footH = Math.Max(4, DeskLayout.FootH * s), neckW = Math.Max(8, p.Neck * s), footW = p.Foot * s;
                Placed pl = new Placed
                {
                    Monitor = p.Monitor, Outer = outer, Screen = screen,
                    Neck = new Rect(Math.Round(cx - neckW / 2), outer.Bottom, Math.Round(neckW), Math.Max(0, deskTop - footH - outer.Bottom)),
                    Foot = new Rect(Math.Round(cx - footW / 2), deskTop - Math.Round(footH), Math.Round(footW), Math.Round(footH)),
                    Plate = new Point(cx, deskTop + (Narrow ? 4 : 8)),
                    PlateHalf = outer.Width / 2
                };
                if (Profile != null)
                    foreach (Zone z in Profile.Zones)
                    {
                        if (!string.IsNullOrEmpty(z.PlateId)) continue;
                        if (!Slotter.Monitors.Holds(p.Monitor, z)) continue;
                        pl.Used = true;
                        Rect r = new Rect(screen.X + screen.Width * z.X / 100 + 2, screen.Y + screen.Height * z.Y / 100 + 2,
                            Math.Max(1, screen.Width * z.W / 100 - 4), Math.Max(1, screen.Height * z.H / 100 - 4));
                        zoneRects.Add(new KeyValuePair<Zone, Rect>(z, Snap(r)));
                    }
                Placements.Add(pl);
                cursorX = left + outer.Width + gapPx;
            }

            double virtualX = cursorX;
            foreach (VirtualPlate plate in pinned)
            {
                MonitorInfo monitor = PlateMonitor(plate);
                DeskLayout.Piece piece = d.Pieces.FirstOrDefault(p => monitor != null && p.Monitor.Key == monitor.Key) ?? tail;
                if (piece == null) continue;
                double bz = Math.Max(3, DeskLayout.Bezel * s), chin = Math.Max(5, DeskLayout.Chin * s);
                double sw = piece.W * s, sh = piece.H * s, left = Math.Round(virtualX);
                double top = Math.Round(oy + d.DeskY * s - DeskLayout.Clearance * s - (sh + bz + chin));
                Rect outer = new Rect(left, top, Math.Round(sw + 2 * bz), Math.Round(sh + bz + chin));
                Rect screen = new Rect(Math.Round(left + bz), Math.Round(top + bz), Math.Round(sw), Math.Round(sh));
                double cx = outer.X + outer.Width / 2, footH = Math.Max(4, DeskLayout.FootH * s);
                double neckW = Math.Max(8, piece.Neck * s), footW = piece.Foot * s;
                Placed pl = new Placed { Monitor = piece.Monitor, VirtualPlate = plate, Outer = outer, Screen = screen,
                    Neck = new Rect(Math.Round(cx - neckW / 2), outer.Bottom, Math.Round(neckW), Math.Max(0, deskTop - footH - outer.Bottom)),
                    Foot = new Rect(Math.Round(cx - footW / 2), deskTop - Math.Round(footH), Math.Round(footW), Math.Round(footH)),
                    Plate = new Point(cx, deskTop + (Narrow ? 4 : 8)), PlateHalf = outer.Width / 2 };
                foreach (Zone z in Profile.Zones.Where(z => string.Equals(z.PlateId, plate.Id, StringComparison.OrdinalIgnoreCase)))
                {
                    pl.Used = true;
                    zoneRects.Add(new KeyValuePair<Zone, Rect>(z, Snap(new Rect(screen.X + screen.Width * z.X / 100 + 2,
                        screen.Y + screen.Height * z.Y / 100 + 2, Math.Max(1, screen.Width * z.W / 100 - 4), Math.Max(1, screen.Height * z.H / 100 - 4)))));
                }
                Placements.Add(pl);
                virtualX = left + outer.Width + gapPx;
            }
            if (tail == null) addGhost = Rect.Empty;
            else
            {
                double bz = Math.Max(3, DeskLayout.Bezel * s), chin = Math.Max(5, DeskLayout.Chin * s);
                double sw = tail.W * s, sh = tail.H * s;
                ghostNeckWidth = Math.Max(8, tail.Neck * s);
                ghostFootWidth = tail.Foot * s;
                addGhost = new Rect(Math.Round(virtualX), Math.Round(oy + d.DeskY * s - DeskLayout.Clearance * s - (sh + bz + chin)),
                    Math.Max(1, Math.Round(sw + 2 * bz)), Math.Max(1, Math.Round(sh + bz + chin)));
            }
        }

        MonitorInfo PlateMonitor(VirtualPlate plate)
        {
            return Monitors.FirstOrDefault(m => string.Equals(m.Key, plate.MonKey, StringComparison.OrdinalIgnoreCase))
                ?? Monitors.FirstOrDefault(m => m.Ordinal == plate.Mon);
        }

        static Rect Snap(Rect r) { return new Rect(Math.Round(r.X), Math.Round(r.Y), Math.Max(1, Math.Round(r.Width)), Math.Max(1, Math.Round(r.Height))); }

        Brush B(string key) { return Ui.B(key); }

        protected override void OnRender(DrawingContext dc)
        {
            double W = RenderSize.Width, H = RenderSize.Height;
            dc.DrawRectangle(Transparent, null, new Rect(0, 0, W, H));

            LinearGradientBrush surface = Vertical(Ui.C("B.Desk"), Ui.C("B.Desk2"));
            dc.DrawRectangle(surface, null, new Rect(0, deskTop, W, Math.Max(0, H - deskTop)));
            foreach (Placed p in Placements)
            {
                bool off = !p.Monitor.Online;
                LinearGradientBrush neck = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(1, 0) };
                neck.GradientStops.Add(new GradientStop(Ui.C("B.StandShade"), 0));
                neck.GradientStops.Add(new GradientStop(Ui.C("B.StandHi"), 0.45));
                neck.GradientStops.Add(new GradientStop(Ui.C("B.StandShade"), 1));
                dc.DrawRectangle(neck, null, p.Neck);
                dc.DrawRoundedRectangle(Vertical(Ui.C("B.StandHi"), Ui.C("B.Stand")), new Pen(B("B.FootEdge"), 1), Half(p.Foot), 3, 3);

                LinearGradientBrush bezel = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(0, 1) };
                bezel.GradientStops.Add(new GradientStop(Ui.C("B.BezelTop"), 0));
                bezel.GradientStops.Add(new GradientStop(Ui.C("B.Bezel"), 0.18));
                Pen edge = new Pen(B("B.BezelEdge"), 1);
                if (off) edge.DashStyle = new DashStyle(new double[] { 3, 3 }, 0);
                if (p.VirtualPlate != null) edge = new Pen(B("B.Selection"), 1.5) { DashStyle = new DashStyle(new double[] { 5, 3 }, 0) };
                double rm = Ui.D("R.Monitor");
                dc.DrawRoundedRectangle(off ? B("B.Bezel") : bezel, edge, Half(p.Outer), rm, rm);

                Brush screen;
                if (off) screen = B("B.ScreenOff");
                else if (p.VirtualPlate != null || (Profile != null && !p.Used)) screen = B("B.ScreenUnused");
                else
                {
                    LinearGradientBrush g = new LinearGradientBrush { StartPoint = new Point(0.41, 0), EndPoint = new Point(0.59, 1) };
                    g.GradientStops.Add(new GradientStop(Ui.C("B.ScreenTop"), 0));
                    g.GradientStops.Add(new GradientStop(Ui.C("B.Screen"), 0.6));
                    screen = g;
                }
                dc.DrawRectangle(screen, null, p.Screen);

                if (p.VirtualPlate != null && !p.Used)
                {
                    bool compact = p.Screen.Width < 130;
                    FormattedText label = Txt(PlateName(p.VirtualPlate), compact ? 11 : 12, FontWeights.SemiBold, B("B.Ink2"), Math.Max(1, p.Screen.Width - 16));
                    double stackHeight = label.Height + (compact ? 4 : 8) + (compact ? 38 : 36);
                    dc.DrawText(label, new Point(p.Screen.X + (p.Screen.Width - label.Width) / 2, p.Screen.Y + (p.Screen.Height - stackHeight) / 2));
                }
                else if (p.VirtualPlate == null && Profile != null && !p.Used)
                {
                    FormattedText note = Txt("Not used by " + Profile.Name, 12, FontWeights.Normal, B("B.Ink3"));
                    note.MaxTextWidth = Math.Max(1, p.Screen.Width - 16);
                    note.TextAlignment = TextAlignment.Center;
                    dc.DrawText(note, new Point(p.Screen.X + 8, p.Screen.Y + p.Screen.Height / 2 - note.Height - 2));
                }
            }

            foreach (KeyValuePair<Zone, Rect> zr in zoneRects) DrawZone(dc, zr.Key, zr.Value);

            foreach (Placed p in Placements)
            {
                if (p.VirtualPlate == null && !p.Monitor.Online && !Narrow) DrawPill(dc, p.Screen);
                DrawPlate(dc, p);
            }
            if (!addGhost.IsEmpty)
            {
                double footH = Math.Max(4, DeskLayout.FootH * Scale), neckW = ghostNeckWidth, footW = ghostFootWidth;
                double cx = addGhost.X + addGhost.Width / 2;
                dc.DrawRectangle(Vertical(Ui.C("B.StandShade"), Ui.C("B.StandHi")), null,
                    new Rect(cx - neckW / 2, addGhost.Bottom, neckW, Math.Max(0, deskTop - footH - addGhost.Bottom)));
                dc.DrawRoundedRectangle(Vertical(Ui.C("B.StandHi"), Ui.C("B.Stand")), new Pen(B("B.FootEdge"), 1),
                    Half(new Rect(cx - footW / 2, deskTop - footH, footW, footH)), 3, 3);
                dc.DrawRoundedRectangle(B("B.ScreenUnused"), Dashed(B("B.Ink3"), 1.5, 5, 3), Half(addGhost), Ui.D("R.Monitor"), Ui.D("R.Monitor"));
                FormattedText plus = Txt("+", 28, FontWeights.Normal, B("B.Ink2"));
                FormattedText label = Txt("Virtual desktop", 12, FontWeights.SemiBold, B("B.Ink2"), addGhost.Width);
                dc.DrawText(plus, new Point(addGhost.X + (addGhost.Width - plus.Width) / 2, addGhost.Y + addGhost.Height / 2 - plus.Height));
                dc.DrawText(label, new Point(addGhost.X + (addGhost.Width - label.Width) / 2, addGhost.Y + addGhost.Height / 2 + 5));
                FormattedText ghostName = Txt("Add a desktop", 11, FontWeights.Normal, B("B.Ink2"), addGhost.Width);
                dc.DrawText(ghostName, new Point(cx - ghostName.Width / 2, deskTop + (Narrow ? 4 : 8)));
            }
        }

        static readonly Brush Transparent = Brushes.Transparent;

        static LinearGradientBrush Vertical(Color a, Color b)
        {
            return new LinearGradientBrush(a, b, new Point(0, 0), new Point(0, 1));
        }

        static Rect Half(Rect r) { return new Rect(r.X + 0.5, r.Y + 0.5, Math.Max(0, r.Width - 1), Math.Max(0, r.Height - 1)); }

        void DrawZone(DrawingContext dc, Zone z, Rect r)
        {
            MonitorInfo m = Slotter.Monitors.Find(Monitors, z);
            bool off = m != null && !m.Online;
            bool sel = z == Selected;
            bool empty = string.IsNullOrEmpty(z.Prog);
            string fault = Fault(z);
            double rz = Ui.D("R.Zone");

            Brush fill = off ? Transparent : fault != null ? B("B.ZoneFault") : empty ? B("B.ZoneEmpty") : B("B.Zone");
            Pen line;
            if (fault != null) line = Dashed(B("B.Error"), 2, 4, 3);
            else if (off) line = sel ? new Pen(B("B.Selection"), 2) : Dashed(B("B.ZoneOfflineLine"), 1, 3, 3);
            else if (sel) line = new Pen(B("B.Selection"), 1);
            else if (z == hover) line = new Pen(B("B.ZoneHover"), 1);
            else if (empty) line = Dashed(B("B.ZoneEmptyLine"), 1, 3, 3);
            else line = new Pen(B("B.ZoneLine"), 1);
            dc.DrawRoundedRectangle(fill, line, Inset(r, line.Thickness), rz, rz);
            if (sel && !off)
            {
                Rect ring = Inset(r, fault != null ? 6 : 4);
                if (ring.Width > 0 && ring.Height > 0) dc.DrawRoundedRectangle(null, new Pen(B("B.Selection"), 2), ring, 2, 2);
            }
            if (sel && IsKeyboardFocused)
                dc.DrawRoundedRectangle(null, new Pen(B("B.Ink"), 2), new Rect(r.X - 3, r.Y - 3, r.Width + 6, r.Height + 6), 4, 4);

            ProgItem prog = empty ? null : FindProg(z.Prog);
            string name = empty ? "Empty" : (prog == null ? z.Prog : prog.Name);
            // The selected zone keeps the large name and the exe from about 100 wide, so the zone
            // being edited always says what it launches.
            bool roomy = sel ? r.Width >= 100 && r.Height >= 56 : r.Width >= 110 && r.Height >= 56;
            double fs = r.Width > 150 && r.Height > 120 ? 17 : roomy ? 15 : 13;
            double padX = roomy ? 8 : r.Width < 36 ? 2 : 4, padY = roomy ? 7 : Math.Max(0, Math.Min(4, (r.Height - 18) / 2));

            if (fault == null) dc.PushClip(new RectangleGeometry(r, rz, rz));
            double y = r.Y + padY;

            string n = (IndexOf(z) + 1).ToString(CultureInfo.InvariantCulture);
            FormattedText num = Txt(n, r.Width < 36 ? 11 : 13, FontWeights.ExtraBold, sel ? B("B.SelectionInk") : B("B.Ink"));
            double chipW = Math.Min(Math.Max(0, r.Width - padX * 2), Math.Max(22, num.Width + 10));
            double chipH = Math.Min(22, Math.Max(0, r.Height - padY * 2));
            dc.DrawRoundedRectangle(sel ? B("B.Selection") : B("B.ZoneChip"), null, new Rect(r.X + padX, y, chipW, chipH), 3, 3);
            dc.DrawText(num, new Point(r.X + padX + (chipW - num.Width) / 2, y + (chipH - num.Height) / 2));

            FormattedText app = Txt(name, fs, empty ? FontWeights.SemiBold : FontWeights.Bold, empty ? B("B.Ink2") : B("B.Ink"));
            app.MaxLineCount = 1;
            app.Trimming = TextTrimming.CharacterEllipsis;
            // Too short to stack chip over name: the name sits beside the number instead of on the
            // bottom border. Either way it shows only when a few letters fit.
            bool stacked = r.Height >= padY * 2 + 22 + 3 + app.Height;
            double nameX = stacked ? r.X + padX : r.X + padX + chipW + 6;
            double room = r.Right - padX - nameX;
            bool fits = room >= 24;
            if (fits)
            {
                app.MaxTextWidth = Math.Max(1, room);
                dc.DrawText(app, new Point(nameX, stacked ? y + 22 + 3 : y + (22 - app.Height) / 2));
            }
            y += 22 + 3 + (stacked && fits ? app.Height + 3 : 0);

            if (fault != null)
            {
                FormattedText why = Txt(fault, 11, FontWeights.SemiBold, B("B.Error"));
                why.MaxTextWidth = Math.Min(260, Math.Max(120, r.Width - padX * 2));
                dc.DrawText(why, new Point(r.X + padX, y));
            }
            else if (roomy && stacked && fits)
            {
                string sub = prog != null ? System.IO.Path.GetFileName(prog.Exe ?? "") : "Drop target";
                FormattedText path = Txt(sub, 11, FontWeights.Normal, B("B.Ink2"));
                path.MaxTextWidth = Math.Max(1, r.Width - padX * 2);
                path.MaxLineCount = 1;
                path.Trimming = TextTrimming.CharacterEllipsis;
                if (y + path.Height <= r.Bottom - 2) dc.DrawText(path, new Point(r.X + padX, y));
            }
            if (fault == null) dc.Pop();
        }

        static Rect Inset(Rect r, double t)
        {
            double h = t / 2;
            return new Rect(r.X + h, r.Y + h, Math.Max(0, r.Width - t), Math.Max(0, r.Height - t));
        }

        static Pen Dashed(Brush b, double thickness, double dash, double gap)
        {
            // Flat caps: the default square cap grows every dash by the pen's width and closes the gaps.
            return new Pen(b, thickness) { DashStyle = new DashStyle(new double[] { dash / thickness, gap / thickness }, 0), DashCap = PenLineCap.Flat };
        }

        void DrawPill(DrawingContext dc, Rect screen)
        {
            FormattedText t = Txt("DISCONNECTED", 11, FontWeights.Bold, B("B.Ink"));
            double w = t.Width + 12, h = t.Height + 4;
            Rect pill = new Rect(Math.Round(screen.X + (screen.Width - w) / 2), Math.Round(screen.Y - 10), Math.Round(w), Math.Round(h));
            dc.DrawRoundedRectangle(B("B.Stand"), Dashed(B("B.Ink2"), 1, 3, 2), Half(pill), 3, 3);
            dc.DrawText(t, new Point(pill.X + 6, pill.Y + 2));
        }

        void DrawPlate(DrawingContext dc, Placed p)
        {
            MonitorInfo m = p.Monitor;
            FormattedText tag = m.Online ? null : Txt("DISCONNECTED", 11, FontWeights.SemiBold, B("B.Ink2"), p.Outer.Width / 2 - 16);
            double tagW = tag == null ? 0 : tag.Width + 12 + 4;
            FormattedText name = Txt(p.VirtualPlate == null ? m.Name : PlateName(p.VirtualPlate), 13, FontWeights.Bold, B("B.Ink"), p.Outer.Width - tagW);
            double x = p.Plate.X - (name.Width + tagW) / 2;
            dc.DrawText(name, new Point(x, p.Plate.Y));
            if (tag != null)
            {
                Rect box = new Rect(Math.Round(x + name.Width + 4), Math.Round(p.Plate.Y), Math.Round(tag.Width + 12), Math.Round(tag.Height + 2));
                dc.DrawRoundedRectangle(null, Dashed(B("B.Ink3"), 1, 3, 2), Half(box), 3, 3);
                dc.DrawText(tag, new Point(box.X + 6, box.Y + 1));
            }
            if (p.VirtualPlate != null)
            {
                FormattedText badge = Txt(PlateDesktopLabel(p), 10, FontWeights.SemiBold, B("B.Ink2"), p.Outer.Width - 23);
                Rect bench = VirtualBenchBounds(p.VirtualPlate.Id);
                double left = p.Plate.X - (badge.Width + 5 + bench.Width) / 2;
                dc.DrawText(badge, new Point(left, p.Plate.Y + name.Height + 1));
                dc.DrawRoundedRectangle(null, new Pen(B("B.Rule"), 1), Half(bench), 3, 3);
                Pen icon = new Pen(B("B.Ink2"), 1.2) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
                double cx = bench.X + bench.Width / 2, cy = bench.Y + bench.Height / 2;
                dc.DrawLine(icon, new Point(cx, cy - 4), new Point(cx, cy + 2));
                dc.DrawLine(icon, new Point(cx - 2.5, cy - 0.5), new Point(cx, cy + 2));
                dc.DrawLine(icon, new Point(cx + 2.5, cy - 0.5), new Point(cx, cy + 2));
                dc.DrawLine(icon, new Point(cx - 4, cy + 4), new Point(cx + 4, cy + 4));
                dc.DrawLine(icon, new Point(cx - 4, cy + 4), new Point(cx - 4, cy + 2));
                dc.DrawLine(icon, new Point(cx + 4, cy + 4), new Point(cx + 4, cy + 2));
                return;
            }
            string detail = m.PixelW > 0 ? m.Resolution : "";
            if (m.HasSize) detail += (detail.Length > 0 ? " · " : "") + m.Diagonal + " in";
            if (detail.Length > 0)
            {
                FormattedText d = Txt(detail, 11, FontWeights.Normal, B("B.Ink2"), p.Outer.Width);
                dc.DrawText(d, new Point(p.Plate.X - d.Width / 2, p.Plate.Y + name.Height + 1));
            }
        }

        FormattedText Txt(string text, double size, FontWeight weight, Brush brush, double maxWidth = double.PositiveInfinity)
        {
            FormattedText formatted = new FormattedText(text ?? "", CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                new Typeface(Ui.UiFont, FontStyles.Normal, weight, FontStretches.Normal), size, brush,
                VisualTreeHelper.GetDpi(this).PixelsPerDip);
            if (!double.IsPositiveInfinity(maxWidth))
            {
                formatted.MaxTextWidth = Math.Max(1, maxWidth);
                formatted.MaxLineCount = 1;
                formatted.Trimming = TextTrimming.CharacterEllipsis;
            }
            return formatted;
        }

        ProgItem FindProg(string name)
        {
            foreach (ProgItem p in Library) if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase)) return p;
            return null;
        }

        int IndexOf(Zone z) { return Profile == null ? 0 : Profile.Zones.IndexOf(z); }

        Zone HitZone(Point p)
        {
            for (int i = zoneRects.Count - 1; i >= 0; i--)
                if (zoneRects[i].Value.Contains(p)) return zoneRects[i].Key;
            return null;
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            Zone h = HitZone(e.GetPosition(this));
            Cursor = h != null ? Cursors.Hand : null;
            if (h != hover) { hover = h; InvalidateVisual(); }
        }

        protected override void OnMouseLeave(MouseEventArgs e)
        {
            base.OnMouseLeave(e);
            if (hover != null) { hover = null; InvalidateVisual(); }
        }

        protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
        {
            base.OnMouseLeftButtonDown(e);
            Point point = e.GetPosition(this);
            if (addGhost.Contains(point)) { if (VirtualAddClicked != null) VirtualAddClicked(); e.Handled = true; return; }
            foreach (Placed p in Placements.Where(p => p.VirtualPlate != null))
            {
                if (!p.Used && p.Outer.Contains(point)) { if (VirtualSetupClicked != null) VirtualSetupClicked(p.VirtualPlate); e.Handled = true; return; }
                Rect name = VirtualNameBounds(p.VirtualPlate.Id);
                if (name.Contains(point) && e.ClickCount > 1) { if (VirtualRenameClicked != null) VirtualRenameClicked(p.VirtualPlate); e.Handled = true; return; }
                Rect action = VirtualBenchBounds(p.VirtualPlate.Id);
                if (action.Contains(point) && VirtualBenchClicked != null) { VirtualBenchClicked(p.VirtualPlate); e.Handled = true; return; }
            }
            Zone hit = HitZone(point);
            if (hit == null) return;
            Select(hit);
        }

        protected override void OnPreviewKeyDown(KeyEventArgs e)
        {
            base.OnPreviewKeyDown(e);
            if (Profile == null || Profile.Zones.Count == 0) return;
            int step = e.Key == Key.Left || e.Key == Key.Up ? -1 : e.Key == Key.Right || e.Key == Key.Down ? 1 : 0;
            if (step == 0) return;
            int i = Profile.Zones.IndexOf(Selected);
            i = i < 0 ? 0 : (i + step + Profile.Zones.Count) % Profile.Zones.Count;
            Select(Profile.Zones[i]);
            e.Handled = true;
        }

        public void Select(Zone z)
        {
            Selected = z;
            Describe();
            InvalidateVisual();
            if (ZoneClicked != null) ZoneClicked(z);
        }

        protected override void OnGotKeyboardFocus(KeyboardFocusChangedEventArgs e) { base.OnGotKeyboardFocus(e); InvalidateVisual(); }
        protected override void OnLostKeyboardFocus(KeyboardFocusChangedEventArgs e) { base.OnLostKeyboardFocus(e); InvalidateVisual(); }
    }
}
