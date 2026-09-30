using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace Snappy
{
    // A rectangular slot on a monitor, as a percentage of that monitor's working area.
    public class Zone
    {
        public string Name;
        public int Mon;
        public string MonKey;
        public double X, Y, W, H;
        public string Prog; // library program name, or null if this zone is a manual snap target only

        public Zone Clone()
        {
            return new Zone { Name = Name, Mon = Mon, MonKey = MonKey, X = X, Y = Y, W = W, H = H, Prog = Prog };
        }
    }

    // A reusable named program in the [Programs] library.
    public class ProgItem
    {
        public string Name { get; set; }
        public string Exe { get; set; }
        public string Args { get; set; }

        // WPF falls back to ToString() for a ListBoxItem's accessible name.
        public override string ToString() { return Name; }
    }

    public class Profile
    {
        public string Name { get; set; }
        public List<Zone> Zones = new List<Zone>();

        public Profile Clone()
        {
            Profile p = new Profile { Name = Name };
            foreach (Zone z in Zones) p.Zones.Add(z.Clone());
            return p;
        }

        // WPF falls back to ToString() for a ListBoxItem's accessible name.
        public override string ToString() { return Name; }
    }

    public class LaunchResult
    {
        public int Planned, Placed;
        public string FirstError;
    }

    // profiles.ini read/write and the domain queries every window needs. Carried over
    // from the WinForms build untouched — this is a presentation-layer port, not a
    // rewrite of what Snappy does.
    public static class Config
    {
        [DllImport("kernel32", CharSet = CharSet.Unicode)]
        static extern int GetPrivateProfileString(string section, string key, string def, StringBuilder ret, int size, string path);
        [DllImport("kernel32", CharSet = CharSet.Unicode)]
        static extern bool WritePrivateProfileString(string section, string key, string val, string path);

        public static readonly string IniPath = Path.Combine(AppContext.BaseDirectory, "profiles.ini");

        public static string IniRead(string section, string key, string def)
        {
            StringBuilder sb = new StringBuilder(4096);
            GetPrivateProfileString(section, key, def, sb, sb.Capacity, IniPath);
            return sb.ToString();
        }

        public static bool IniWrite(string section, string key, string val)
        {
            try
            {
                bool ok = WritePrivateProfileString(section, key, val, IniPath);
                if (!ok) Log.Write("ini write failed: [" + section + "] " + key);
                return ok;
            }
            catch (Exception ex) { Log.Write("ini write: " + ex.Message); return false; }
        }

        public static void EnsureDefault()
        {
            if (File.Exists(IniPath)) return;
            try
            {
                File.WriteAllText(IniPath, string.Join(Environment.NewLine, new string[] {
                    "; Snappy config -- edit via the tray Settings window, or by hand here.",
                    "; Zone<N> = Monitor,XPct,YPct,WPct,HPct   (percent of that monitor's work area, monitor is 1-based)",
                    "; App<N>  = ExePath,Args,ZoneName          (Args may be blank; same exe may repeat)",
                    "[Profiles]",
                    "List=Example",
                    "",
                    "[Example]",
                    "Zone1=1,0,0,50,100",
                    "Zone2=1,50,0,50,100",
                    "Prog1=Notepad",
                    "Prog2=Paint",
                    "",
                    "[Panel]",
                    "LastProfile=Example",
                    "",
                    "[Settings]",
                    "StartWithWindows=1",
                    "HotkeyEnabled=1",
                    "Appearance=follow",
                    "",
                    "[Programs]",
                    "Count=2",
                    "Name1=Notepad",
                    "Exe1=notepad.exe",
                    "Args1=",
                    "Name2=Paint",
                    "Exe2=mspaint.exe",
                    "Args2=",
                    "" }));
            }
            catch (Exception ex) { Log.Write("default ini: " + ex.Message); }
        }

        public static List<Profile> ReadProfiles()
        {
            List<Profile> list = new List<Profile>();
            try
            {
                foreach (string raw in IniRead("Profiles", "List", "").Split(','))
                {
                    string name = raw.Trim();
                    if (name.Length == 0) continue;
                    Profile p = new Profile { Name = name };
                    for (int i = 1; ; i++)
                    {
                        string v = IniRead(name, "Zone" + i, "");
                        if (v.Length == 0) break;
                        string[] parts = v.Split(',');
                        int mon; double x, y, w, h;
                        if (parts.Length >= 5
                            && int.TryParse(parts[0].Trim(), out mon)
                            && double.TryParse(parts[1].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out x)
                            && double.TryParse(parts[2].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out y)
                            && double.TryParse(parts[3].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out w)
                            && double.TryParse(parts[4].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out h)
                            && Finite(x) && Finite(y) && Finite(w) && Finite(h))
                        {
                            x = Clamp(x, 0, 99); y = Clamp(y, 0, 99);
                            w = Clamp(w, 1, 100 - x); h = Clamp(h, 1, 100 - y);
                            string prog = IniRead(name, "Prog" + i, "").Trim();
                            string monKey = IniRead(name, "MonKey" + i, "").Trim();
                            p.Zones.Add(new Zone { Name = "Zone" + i, Mon = mon, MonKey = monKey, X = x, Y = y, W = w, H = h, Prog = prog.Length > 0 ? prog : null });
                        }
                        else Log.Write("bad zone line in [" + name + "]: " + v);
                    }
                    list.Add(p);
                }
            }
            catch (Exception ex) { Log.Write("config load: " + ex.Message); }
            return list;
        }

        public static bool SaveProfiles(List<Profile> list)
        {
            try
            {
                bool ok = true;
                foreach (string raw in IniRead("Profiles", "List", "").Split(','))
                {
                    string old = raw.Trim();
                    if (old.Length > 0) ok &= WritePrivateProfileString(old, null, null, IniPath);
                }
                List<string> names = new List<string>();
                foreach (Profile p in list) names.Add(p.Name);
                ok &= IniWrite("Profiles", "List", string.Join(",", names.ToArray()));
                foreach (Profile p in list)
                {
                    for (int i = 0; i < p.Zones.Count; i++)
                    {
                        Zone z = p.Zones[i];
                        ok &= IniWrite(p.Name, "Zone" + (i + 1), string.Format(CultureInfo.InvariantCulture, "{0},{1},{2},{3},{4}", z.Mon, Trim(z.X), Trim(z.Y), Trim(z.W), Trim(z.H)));
                        ok &= IniWrite(p.Name, "MonKey" + (i + 1), z.MonKey ?? "");
                        if (!string.IsNullOrEmpty(z.Prog)) ok &= IniWrite(p.Name, "Prog" + (i + 1), z.Prog);
                    }
                }
                return ok;
            }
            catch (Exception ex) { Log.Write("save profiles: " + ex.Message); return false; }
        }

        static string Trim(double d) { return d.ToString("0.##", CultureInfo.InvariantCulture); }

        public static List<ProgItem> ReadPrograms()
        {
            List<ProgItem> list = new List<ProgItem>();
            try
            {
                int n; int.TryParse(IniRead("Programs", "Count", "0"), out n);
                for (int i = 1; i <= n; i++)
                {
                    string name = IniRead("Programs", "Name" + i, "");
                    if (name.Length == 0) continue;
                    list.Add(new ProgItem { Name = name, Exe = IniRead("Programs", "Exe" + i, ""), Args = IniRead("Programs", "Args" + i, "") });
                }
            }
            catch (Exception ex) { Log.Write("read programs: " + ex.Message); }
            return list;
        }

        public static bool WritePrograms(List<ProgItem> list)
        {
            try
            {
                bool ok = WritePrivateProfileString("Programs", null, null, IniPath);
                ok &= IniWrite("Programs", "Count", list.Count.ToString(CultureInfo.InvariantCulture));
                for (int i = 0; i < list.Count; i++)
                {
                    ok &= IniWrite("Programs", "Name" + (i + 1), list[i].Name);
                    ok &= IniWrite("Programs", "Exe" + (i + 1), list[i].Exe);
                    ok &= IniWrite("Programs", "Args" + (i + 1), list[i].Args);
                }
                return ok;
            }
            catch (Exception ex) { Log.Write("write programs: " + ex.Message); return false; }
        }

        public static double Clamp(double value, double min, double max) { return Math.Max(min, Math.Min(max, value)); }
        static bool Finite(double value) { return !double.IsNaN(value) && !double.IsInfinity(value); }

        public static Profile FindProfile(List<Profile> profiles, string name)
        {
            foreach (Profile p in profiles) if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase)) return p;
            return null;
        }

        public static int ResolveScreenIndex(Zone z, Screen[] screens)
        {
            if (!string.IsNullOrEmpty(z.MonKey))
            {
                for (int i = 0; i < screens.Length; i++)
                    if (z.MonKey == screens[i].Bounds.Width + "x" + screens[i].Bounds.Height) return i;
                return -1;
            }
            int idx = z.Mon - 1;
            return idx >= 0 && idx < screens.Length ? idx : -1;
        }

        public static bool ZoneInSlot(Zone z, string slotKey, int slotOrdinal)
        {
            if (!string.IsNullOrEmpty(z.MonKey)) return z.MonKey == slotKey;
            return z.Mon == slotOrdinal;
        }

        // A zone is keyed on the monitor's resolution, so the name comes from whichever attached
        // screen currently has that size: the family's shared name for its EDID identity ("LG CX"),
        // else the panel's own EDID name. A remote session or a display that is away has no identity,
        // so it reads as the resolution rather than borrowing another panel's name.
        public static string MonitorLabel(string monKey)
        {
            if (string.IsNullOrEmpty(monKey)) return "RDP";
            foreach (Screen screen in Screen.AllScreens)
            {
                if (screen.Bounds.Width + "x" + screen.Bounds.Height != monKey) continue;
                string identity, edidName;
                if (Ykit.DeskDisplayIdentity.ForDevice(screen.DeviceName, out identity, out edidName))
                    return Ykit.DeskDisplayNames.NameFor(identity, edidName.Length > 0 ? edidName : monKey);
                return SystemInformation.TerminalServerSession ? "RDP" : monKey;
            }
            return monKey;
        }

        public static bool ProfileVisible(Profile p, Screen[] screens)
        {
            if (p.Zones.Count == 0) return true;
            foreach (Zone z in p.Zones) if (ResolveScreenIndex(z, screens) < 0) return false;
            return true;
        }

        public static string ProfileMonitorLabel(Profile p, Screen[] screens)
        {
            List<string> labels = new List<string>();
            foreach (Zone z in p.Zones)
            {
                string key = z.MonKey;
                if (string.IsNullOrEmpty(key))
                {
                    int idx = ResolveScreenIndex(z, screens);
                    if (idx >= 0) key = screens[idx].Bounds.Width + "x" + screens[idx].Bounds.Height;
                }
                string label = MonitorLabel(key);
                if (!labels.Contains(label)) labels.Add(label);
            }
            if (labels.Count == 0) return "Unassigned";
            labels.Sort(StringComparer.OrdinalIgnoreCase);
            return string.Join(" + ", labels.ToArray());
        }
    }
}
