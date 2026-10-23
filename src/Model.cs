using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace Slotter
{
    // A rectangular slot on a monitor, as a percentage of that monitor's working area.
    public class Zone
    {
        public string Name;
        public int Mon;
        public string MonKey;
        public double X, Y, W, H;
        public string Prog; // library program name, or null if this zone is a manual snap target only
        public string PlateId;

        public Zone Clone()
        {
            return new Zone { Name = Name, Mon = Mon, MonKey = MonKey, X = X, Y = Y, W = W, H = H, Prog = Prog, PlateId = PlateId };
        }

        public Zone Clamped()
        {
            var zone = Clone();
            zone.X = Config.Clamp(double.IsFinite(X) ? X : 0, 0, 99);
            zone.Y = Config.Clamp(double.IsFinite(Y) ? Y : 0, 0, 99);
            zone.W = Config.Clamp(double.IsFinite(W) ? W : 0, 1, 100 - zone.X);
            zone.H = Config.Clamp(double.IsFinite(H) ? H : 0, 1, 100 - zone.Y);
            return zone;
        }
    }

    // A reusable named program in the [Programs] library.
    public class ProgItem
    {
        public Guid Id { get; set; } = Guid.NewGuid();
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
        public List<VirtualPlate> VirtualPlates = new List<VirtualPlate>();

        public Profile Clone()
        {
            Profile p = new Profile { Name = Name };
            foreach (Zone z in Zones) p.Zones.Add(z.Clone());
            foreach (VirtualPlate plate in VirtualPlates) p.VirtualPlates.Add(plate.Clone());
            return p;
        }

        // WPF falls back to ToString() for a ListBoxItem's accessible name.
        public override string ToString() { return Name; }
    }

    public class VirtualPlate
    {
        public string Id;
        public string Name;
        public string MonKey;
        public int Mon;
        public string DesktopId;
        public bool? AutoName;
        public string ClosedDesktopLabel;
        public bool FollowsDesktopName { get { return AutoName ?? System.Text.RegularExpressions.Regex.IsMatch(Name ?? "", @"^Desktop [1-9][0-9]*$"); } }

        public VirtualPlate Clone() { return (VirtualPlate)MemberwiseClone(); }
        public bool Benched { get { return string.IsNullOrEmpty(DesktopId); } }
    }

    public sealed class DesktopSetup
    {
        public string Name;
        public List<Zone> Zones = new List<Zone>();
    }

    public class LaunchResult
    {
        public int Planned, Placed;
        public string FirstError;
        public bool Cancelled;
    }

    // profiles.ini read/write and the domain queries every window needs. Carried over
    // from the WinForms build untouched — this is a presentation-layer port, not a
    // rewrite of what Slotter does.
    public static class Config
    {
        public static List<DesktopSetup> ReadDesktopSetups()
        {
            var result = new List<DesktopSetup>();
            int count;
            int.TryParse(IniRead("DesktopSetups", "Count", "0"), out count);
            for (int n = 1; n <= Math.Min(1000, count); n++)
            {
                var setup = new DesktopSetup { Name = IniRead("DesktopSetups", "Name" + n, "") };
                int zones;
                int.TryParse(IniRead("DesktopSetups", "ZoneCount" + n, "0"), out zones);
                for (int i = 1; i <= Math.Min(400, zones); i++)
                {
                    string key = n + "_" + i;
                    string[] parts = IniRead("DesktopSetups", "Zone" + key, "").Split(',');
                    double x, y, w, h;
                    if (parts.Length != 4 || !double.TryParse(parts[0], NumberStyles.Float, CultureInfo.InvariantCulture, out x)
                        || !double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out y)
                        || !double.TryParse(parts[2], NumberStyles.Float, CultureInfo.InvariantCulture, out w)
                        || !double.TryParse(parts[3], NumberStyles.Float, CultureInfo.InvariantCulture, out h)
                        || !double.IsFinite(x) || !double.IsFinite(y) || !double.IsFinite(w) || !double.IsFinite(h)
                        || x < 0 || y < 0 || w < 1 || h < 1 || x + w > 100.05 || y + h > 100.05) continue;
                    setup.Zones.Add(new Zone { Mon = 1, X = x, Y = y, W = w, H = h, Prog = IniRead("DesktopSetups", "Program" + key, "") }.Clamped());
                }
                if (!string.IsNullOrEmpty(setup.Name) && setup.Zones.Count > 0) result.Add(setup);
            }
            return result;
        }

        public static bool WriteDesktopSetups(List<DesktopSetup> setups)
        {
            bool ok = true;
            for (int index = 0; index < setups.Count; index++)
            {
                int n = index + 1;
                DesktopSetup setup = setups[index];
                ok &= IniWrite("DesktopSetups", "Name" + n, setup.Name);
                ok &= IniWrite("DesktopSetups", "ZoneCount" + n, setup.Zones.Count.ToString(CultureInfo.InvariantCulture));
                for (int i = 0; i < setup.Zones.Count; i++)
                {
                    Zone zone = setup.Zones[i].Clamped();
                    string key = n + "_" + (i + 1);
                    ok &= IniWrite("DesktopSetups", "Zone" + key, string.Join(",", new[] { zone.X, zone.Y, zone.W, zone.H }.Select(v => v.ToString(CultureInfo.InvariantCulture))));
                    ok &= IniWrite("DesktopSetups", "Program" + key, zone.Prog ?? "");
                }
            }
            return ok && IniWrite("DesktopSetups", "Count", setups.Count.ToString(CultureInfo.InvariantCulture));
        }

        public static bool ReconcileDesktops(Profile profile, DesktopSnapshot snapshot)
        {
            if (snapshot == null || !snapshot.Available) return false;
            bool changed = false;
            foreach (VirtualPlate plate in profile.VirtualPlates)
            {
                if (plate.Benched) continue;
                int index = snapshot.Desktops.FindIndex(d => d.Id.ToString().Equals(plate.DesktopId, StringComparison.OrdinalIgnoreCase));
                if (index < 0)
                {
                    plate.ClosedDesktopLabel = plate.Name;
                    plate.DesktopId = "";
                    changed = true;
                }
                else if (plate.FollowsDesktopName && plate.Name != "Desktop " + (index + 1))
                {
                    plate.Name = "Desktop " + (index + 1);
                    changed = true;
                }
            }
            return changed;
        }
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
                    "; Slotter config -- edit via the tray Settings window, or by hand here.",
                    "; Zone<N> = Monitor,XPct,YPct,WPct,HPct   (percent of that monitor's work area, monitor is 1-based)",
                    "; Prog<N> = <program name from [Programs]>  (which program launches into Zone<N>)",
                    "[Profiles]",
                    "List=Example",
                    "",
                    "[Example]",
                    "",
                    "[Panel]",
                    "LastProfile=Example",
                    "",
                    "[Settings]",
                    "StartWithWindows=0",
                    "HotkeyEnabled=1",
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
                            p.Zones.Add(new Zone { Name = "Zone" + i, Mon = mon, MonKey = monKey, X = x, Y = y, W = w, H = h, Prog = prog.Length > 0 ? prog : null, PlateId = IniRead(name, "PlateId" + i, "").Trim() });
                        }
                        else Log.Write("bad zone line in [" + name + "]: " + v);
                    }
                    list.Add(p);
                    int plateCount;
                    int.TryParse(IniRead(name, "VirtualPlateCount", "0"), out plateCount);
                    for (int i = 1; i <= Math.Max(0, Math.Min(plateCount, 500)); i++)
                    {
                        string id = IniRead(name, "VirtualPlateId" + i, "").Trim();
                        Guid parsed;
                        int plateMon;
                        if (!Guid.TryParse(id, out parsed)) continue;
                        p.VirtualPlates.Add(new VirtualPlate
                        {
                            Id = parsed.ToString(), Name = IniRead(name, "VirtualPlateName" + i, "Desktop").Trim(),
                            Mon = int.TryParse(IniRead(name, "VirtualPlateMonitor" + i, "1"), out plateMon) ? plateMon : 1,
                            MonKey = IniRead(name, "VirtualPlateMonKey" + i, "").Trim(),
                            DesktopId = IniRead(name, "VirtualPlateDesktop" + i, "").Trim(),
                            AutoName = IniRead(name, "VirtualPlateAutoName" + i, "") == "" ? (bool?)null : IniRead(name, "VirtualPlateAutoName" + i, "0") == "1",
                            ClosedDesktopLabel = IniRead(name, "VirtualPlateClosedDesktop" + i, "")
                        });
                    }
                }
            }
            catch (Exception ex) { Log.Write("config load: " + ex.Message); }
            return list;
        }

        public static bool MigrateReservedProfiles(List<Profile> profiles, Dictionary<string, string> bindings)
        {
            Dictionary<string, string> renamed = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (Profile profile in profiles)
            {
                if (!string.Equals(profile.Name, "DesktopBindings", StringComparison.OrdinalIgnoreCase)
                    && !string.Equals(profile.Name, "Shortcuts", StringComparison.OrdinalIgnoreCase)) continue;
                string baseName = profile.Name + " workspace";
                string name = baseName;
                for (int suffix = 2; FindProfile(profiles, name) != null; suffix++)
                    name = baseName + " " + suffix;
                renamed[profile.Name] = name;
                profile.Name = name;
            }
            if (renamed.Count == 0) return true;

            Dictionary<SnapAction, KeyCombo> shortcuts = ShortcutTable.Read();
            bool ok = SaveProfiles(profiles);
            string last = IniRead("Panel", "LastProfile", "");
            string migrated;
            if (renamed.TryGetValue(last, out migrated)) ok &= IniWrite("Panel", "LastProfile", migrated);
            foreach (string id in bindings.Keys.ToArray())
                if (renamed.TryGetValue(bindings[id], out migrated)) bindings[id] = migrated;
            ok &= WriteDesktopBindings(bindings);
            ok &= WriteShortcuts(shortcuts);
            return ok;
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
                        ok &= IniWrite(p.Name, "PlateId" + (i + 1), z.PlateId ?? "");
                        if (!string.IsNullOrEmpty(z.Prog)) ok &= IniWrite(p.Name, "Prog" + (i + 1), z.Prog);
                    }
                    ok &= IniWrite(p.Name, "VirtualPlateCount", p.VirtualPlates.Count.ToString(CultureInfo.InvariantCulture));
                    for (int i = 0; i < p.VirtualPlates.Count; i++)
                    {
                        VirtualPlate plate = p.VirtualPlates[i];
                        ok &= IniWrite(p.Name, "VirtualPlateId" + (i + 1), plate.Id);
                        ok &= IniWrite(p.Name, "VirtualPlateName" + (i + 1), plate.Name);
                        ok &= IniWrite(p.Name, "VirtualPlateMonitor" + (i + 1), plate.Mon.ToString(CultureInfo.InvariantCulture));
                        ok &= IniWrite(p.Name, "VirtualPlateMonKey" + (i + 1), plate.MonKey ?? "");
                        ok &= IniWrite(p.Name, "VirtualPlateDesktop" + (i + 1), plate.DesktopId ?? "");
                        ok &= IniWrite(p.Name, "VirtualPlateAutoName" + (i + 1), plate.FollowsDesktopName ? "1" : "0");
                        ok &= IniWrite(p.Name, "VirtualPlateClosedDesktop" + (i + 1), plate.ClosedDesktopLabel ?? "");
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
                n = Math.Min(n, File.ReadLines(IniPath).Count());
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

        public static Dictionary<string, string> ReadDesktopBindings()
        {
            Dictionary<string, string> bindings = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            string raw = IniRead("DesktopBindings", "List", "");
            foreach (string idText in raw.Split(','))
            {
                Guid id;
                if (!Guid.TryParse(idText.Trim(), out id)) continue;
                string name = IniRead("DesktopBindings", id.ToString(), "").Trim();
                if (name.Length > 0) bindings[id.ToString()] = name;
            }
            return bindings;
        }

        public static bool WriteDesktopBindings(Dictionary<string, string> bindings)
        {
            List<string> entries = new List<string>();
            bool ok = WritePrivateProfileString("DesktopBindings", null, null, IniPath);
            foreach (KeyValuePair<string, string> pair in bindings.OrderBy(x => x.Key, StringComparer.OrdinalIgnoreCase))
            {
                Guid id;
                if (Guid.TryParse(pair.Key, out id) && !string.IsNullOrWhiteSpace(pair.Value))
                {
                    entries.Add(id.ToString());
                    ok &= IniWrite("DesktopBindings", id.ToString(), pair.Value.Trim());
                }
            }
            return ok & IniWrite("DesktopBindings", "List", string.Join(",", entries.ToArray()));
        }

        public static bool WriteShortcuts(Dictionary<SnapAction, KeyCombo> table)
        {
            bool ok = WritePrivateProfileString("Shortcuts", null, null, IniPath);
            foreach (SnapAction action in ShortcutTable.All)
                ok &= IniWrite("Shortcuts", action.ToString(), ShortcutTable.ToIni(table, action));
            return ok;
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
        // screen currently has that size. A display that is away is named from [Monitors], what
        // Slotter saw when it was last connected, else its resolution.
        public static string MonitorLabel(string monKey)
        {
            if (string.IsNullOrEmpty(monKey)) return "RDP";
            foreach (Screen screen in Screen.AllScreens)
            {
                if (screen.Bounds.Width + "x" + screen.Bounds.Height != monKey) continue;
                return DisplayNames.For(screen.DeviceName, SystemInformation.TerminalServerSession ? "RDP" : monKey);
            }
            return Monitors.Label(monKey);
        }

        public static bool ProfileVisible(Profile p, Screen[] screens)
        {
            if (p.Zones.Count == 0) return true;
            foreach (Zone z in p.Zones) if (ResolveScreenIndex(z, screens) < 0) return false;
            return true;
        }

        public static Profile ForDesktop(Profile profile, Guid? desktopId)
        {
            if (profile == null) return profile;
            if (!desktopId.HasValue)
            {
                Profile physical = new Profile { Name = profile.Name };
                physical.Zones.AddRange(profile.Zones.Where(z => string.IsNullOrEmpty(z.PlateId)));
                return physical;
            }
            Dictionary<string, string> pinned = profile.VirtualPlates
                .Where(p => !p.Benched && string.Equals(p.DesktopId, desktopId.Value.ToString(), StringComparison.OrdinalIgnoreCase))
                .GroupBy(p => p.MonKey ?? p.Mon.ToString(CultureInfo.InvariantCulture), StringComparer.OrdinalIgnoreCase)
                .ToDictionary(g => g.Key, g => g.First().Id, StringComparer.OrdinalIgnoreCase);
            if (pinned.Count == 0)
            {
                Profile physical = new Profile { Name = profile.Name };
                physical.Zones.AddRange(profile.Zones.Where(z => string.IsNullOrEmpty(z.PlateId)));
                return physical;
            }
            Profile resolved = new Profile { Name = profile.Name };
            foreach (Zone zone in profile.Zones)
            {
                string key = zone.MonKey ?? zone.Mon.ToString(CultureInfo.InvariantCulture);
                string plate;
                if (pinned.TryGetValue(key, out plate))
                {
                    if (string.Equals(zone.PlateId, plate, StringComparison.OrdinalIgnoreCase)) resolved.Zones.Add(zone);
                }
                else if (string.IsNullOrEmpty(zone.PlateId)) resolved.Zones.Add(zone);
            }
            return resolved;
        }
    }
}
