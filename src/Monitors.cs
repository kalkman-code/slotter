using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows.Forms;

namespace Slotter
{
    public sealed class MonitorInfo
    {
        public string Key;          // "3840x2160": zones remember their monitor by resolution
        public string Name;         // "LG CX"
        public int Ordinal;         // 1-based position in Screen.AllScreens; 0 when disconnected
        public bool Online;
        public System.Drawing.Rectangle Bounds;
        public int PixelW, PixelH;
        public double WidthIn, HeightIn; // physical image size; 0 when the display does not say

        public bool HasSize { get { return WidthIn > 0 && HeightIn > 0; } }
        public string Resolution { get { return PixelW + " × " + PixelH; } }
        public int Diagonal { get { return (int)Math.Round(Math.Sqrt(WidthIn * WidthIn + HeightIn * HeightIn)); } }
    }

    // Every monitor the designer can draw: the connected ones, and any a workspace still names
    // that is not connected now, drawn from what it looked like when it last was, left to right.
    public static class Monitors
    {
        // Set only by offscreen renders, which need a desk that is not the machine's own.
        public static List<MonitorInfo> Override;

        public static List<MonitorInfo> Known(IEnumerable<Profile> profiles)
        {
            List<MonitorInfo> list = Override != null ? new List<MonitorInfo>(Override) : Connected();
            foreach (Profile p in profiles)
                foreach (Zone z in p.Zones)
                {
                    if (string.IsNullOrEmpty(z.MonKey) || Find(list, z) != null) continue;
                    list.Add(Remembered(z.MonKey));
                }
            // Stable: connected monitors keep the OS's left-to-right order, and a remembered one
            // slots back in where it stood; one never seen goes to the right.
            List<MonitorInfo> sorted = new List<MonitorInfo>(list);
            sorted.Sort((a, b) =>
            {
                int ax = a.Bounds.Width > 0 ? a.Bounds.X : int.MaxValue, bx = b.Bounds.Width > 0 ? b.Bounds.X : int.MaxValue;
                return ax != bx ? ax.CompareTo(bx) : list.IndexOf(a).CompareTo(list.IndexOf(b));
            });
            return sorted;
        }

        // Records what each connected monitor looks like, so it can still be drawn and named once
        // it is unplugged. Runs whenever the monitors are listed and when the displays change.
        public static void Remember() { if (Override == null) Connected(); }

        // [Monitors] in profiles.ini, one line per resolution key, hand-editable:
        //   3440x1440=Ultrawide|31.5|13.39|3840|180
        // name | width and height in inches (0 when unknown) | left and top in desktop pixels.
        const string Section = "Monitors";

        static void Record(MonitorInfo m)
        {
            if (SystemInformation.TerminalServerSession) return;
            string line = string.Join("|", new[] { m.Name, Num(m.WidthIn), Num(m.HeightIn),
                m.Bounds.X.ToString(CultureInfo.InvariantCulture), m.Bounds.Y.ToString(CultureInfo.InvariantCulture) });
            if (Config.IniRead(Section, m.Key, "") != line) Config.IniWrite(Section, m.Key, line);
        }

        static string Num(double v) { return Math.Round(v, 2).ToString("0.##", CultureInfo.InvariantCulture); }

        static MonitorInfo Remembered(string key)
        {
            int w, h;
            ParseKey(key, out w, out h);
            MonitorInfo m = new MonitorInfo { Key = key, Name = w > 0 ? w + " × " + h : key, PixelW = w, PixelH = h };
            string[] parts = Config.IniRead(Section, key, "").Split('|');
            if (parts.Length < 5 || parts[0].Trim().Length == 0) return m;
            double wi, hi;
            int x, y;
            m.Name = parts[0].Trim();
            if (double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out wi)
                && double.TryParse(parts[2], NumberStyles.Float, CultureInfo.InvariantCulture, out hi) && wi > 0 && hi > 0)
            { m.WidthIn = wi; m.HeightIn = hi; }
            if (int.TryParse(parts[3], NumberStyles.Integer, CultureInfo.InvariantCulture, out x)
                && int.TryParse(parts[4], NumberStyles.Integer, CultureInfo.InvariantCulture, out y))
                m.Bounds = new System.Drawing.Rectangle(x, y, w, h);
            return m;
        }

        // What a zone's monitor is called, connected or not.
        public static string Label(string key)
        {
            if (string.IsNullOrEmpty(key)) return "RDP";
            if (Override != null)
                foreach (MonitorInfo o in Override) if (o.Key == key) return o.Name;
            return Remembered(key).Name;
        }

        static List<MonitorInfo> Connected()
        {
            List<MonitorInfo> list = new List<MonitorInfo>();
            Screen[] screens = Screen.AllScreens;
            for (int i = 0; i < screens.Length; i++)
            {
                Screen s = screens[i];
                string key = s.Bounds.Width + "x" + s.Bounds.Height;
                MonitorInfo m = new MonitorInfo
                {
                    Key = key, Ordinal = i + 1, Online = true, Bounds = s.Bounds, PixelW = s.Bounds.Width, PixelH = s.Bounds.Height,
                    Name = DisplayNames.For(s.DeviceName, SystemInformation.TerminalServerSession ? "RDP" : s.Bounds.Width + " × " + s.Bounds.Height)
                };
                int wcm, hcm;
                // LG TVs report 160 x 90 cm whatever their real size, so that figure means unknown.
                if (DisplayNames.SizeCm(s.DeviceName, out wcm, out hcm) && !(wcm == 160 && hcm == 90)) { m.WidthIn = wcm / 2.54; m.HeightIn = hcm / 2.54; }
                double diagonal;
                if (double.TryParse(Config.IniRead("DisplaySizes", m.Name, ""), System.Globalization.NumberStyles.Float,
                        System.Globalization.CultureInfo.InvariantCulture, out diagonal) && diagonal > 0)
                {
                    double across = Math.Sqrt((double)m.PixelW * m.PixelW + (double)m.PixelH * m.PixelH);
                    m.WidthIn = diagonal * m.PixelW / across;
                    m.HeightIn = diagonal * m.PixelH / across;
                }
                Record(m);
                list.Add(m);
            }
            list.Sort((a, b) => a.Bounds.X != b.Bounds.X ? a.Bounds.X.CompareTo(b.Bounds.X) : a.Bounds.Y.CompareTo(b.Bounds.Y));
            return list;
        }

        static void ParseKey(string key, out int w, out int h)
        {
            w = h = 0;
            string[] parts = key.Split('x');
            if (parts.Length == 2 && int.TryParse(parts[0], out w) && int.TryParse(parts[1], out h)) return;
            w = h = 0;
        }

        public static bool Holds(MonitorInfo m, Zone z)
        {
            if (m.Online) return Config.ZoneInSlot(z, m.Key, m.Ordinal);
            return z.MonKey == m.Key;
        }

        public static MonitorInfo Find(List<MonitorInfo> list, Zone z)
        {
            foreach (MonitorInfo m in list) if (Holds(m, z)) return m;
            return null;
        }
    }

    // The desk in inches (or, when a display gives no size, in pixels at 96 to the inch, which
    // keeps the same look): each monitor's screen, bezel, stand and foot, all feet on one desk
    // line. The canvas multiplies it by one scale factor.
    public sealed class DeskLayout
    {
        public sealed class Piece
        {
            public MonitorInfo Monitor;
            public double X, Y, W, H;       // screen, inches
            public double Neck, Foot;       // widths, inches
        }

        public const double Bezel = 0.35, Chin = 0.7, FootH = 0.75, Gap = 3.5, Clearance = 2.0;

        public readonly List<Piece> Pieces = new List<Piece>();
        public double Width, DeskY;
        public bool TrueSize;

        public static DeskLayout For(List<MonitorInfo> monitors)
        {
            DeskLayout d = new DeskLayout();
            d.TrueSize = monitors.Count > 0;
            foreach (MonitorInfo m in monitors) if (m.Online && !m.HasSize) d.TrueSize = false;

            MonitorInfo reference = null;
            foreach (MonitorInfo m in monitors) if (m.Online) { reference = m; break; }
            // Inches per pixel on the reference panel: how the OS's vertical offsets between
            // monitors turn into a drop on the desk, and the size guess for a monitor that is
            // not connected now.
            double pitch = 1.0 / 96;
            if (d.TrueSize && reference != null && reference.PixelH > 0) pitch = reference.HeightIn / reference.PixelH;

            double x = 0;
            double minY = double.MaxValue;
            foreach (MonitorInfo m in monitors)
            {
                Piece p = new Piece { Monitor = m };
                if (d.TrueSize && m.HasSize) { p.W = m.WidthIn; p.H = m.HeightIn; }
                else { p.W = Math.Max(1, m.PixelW) * pitch; p.H = Math.Max(1, m.PixelH) * pitch; }
                p.Y = (m.Online || m.Bounds.Width > 0) && reference != null ? (m.Bounds.Y - reference.Bounds.Y) * pitch : 0;
                p.X = x + Bezel;
                x += p.W + 2 * Bezel + Gap;
                p.Neck = Math.Max(2.4, Math.Min(6, p.W * 0.12));
                p.Foot = p.W * 0.37;
                minY = Math.Min(minY, p.Y);
                d.Pieces.Add(p);
            }
            double bottom = 0;
            foreach (Piece p in d.Pieces)
            {
                p.Y -= minY;
                bottom = Math.Max(bottom, p.Y + p.H + Chin);
            }
            d.Width = Math.Max(1, x - Gap);
            d.DeskY = bottom + Clearance;
            return d;
        }
    }
}
