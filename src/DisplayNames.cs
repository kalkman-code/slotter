using System;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Slotter
{
    // What a physical display is called. Identity is the monitor's EDID hardware id plus the UID
    // Windows gave that instance ("GSMC0C8-UID4352"), which survives a re-plug, a reboot and a
    // change of resolution. A name set by hand under [Displays] in profiles.ini wins; otherwise
    // the panel's own EDID name is used.
    public static class DisplayNames
    {
        public static string For(string deviceName, string fallback)
        {
            string identity, edidName;
            byte[] edid;
            if (!ForDevice(deviceName, out identity, out edidName, out edid)) return fallback;
            string stored = Config.IniRead("Displays", identity, "");
            if (stored.Length > 0) return stored;
            return edidName.Length > 0 ? edidName : fallback;
        }

        // The panel's physical image size from EDID bytes 21 and 22, in whole centimetres. Zero in
        // either byte means the display did not say (a projector, or only an aspect ratio).
        public static bool SizeCm(string deviceName, out int widthCm, out int heightCm)
        {
            widthCm = 0;
            heightCm = 0;
            string identity, edidName;
            byte[] edid;
            if (!ForDevice(deviceName, out identity, out edidName, out edid) || edid == null || edid.Length < 23) return false;
            widthCm = edid[21];
            heightCm = edid[22];
            return widthCm > 0 && heightCm > 0;
        }

        const uint EDD_GET_DEVICE_INTERFACE_NAME = 1;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct DISPLAY_DEVICE
        {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
        }

        [DllImport("user32", CharSet = CharSet.Unicode)]
        static extern bool EnumDisplayDevices(string device, uint devNum, ref DISPLAY_DEVICE dd, uint flags);

        // Identity and panel name for a GDI device such as "\\.\DISPLAY1" (Screen.DeviceName). A
        // display with no readable EDID (a virtual adapter, Remote Desktop's Default_Monitor) has none.
        static bool ForDevice(string deviceName, out string identity, out string edidName, out byte[] edid)
        {
            identity = "";
            edidName = "";
            edid = null;
            try
            {
                DISPLAY_DEVICE mon = new DISPLAY_DEVICE();
                mon.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
                if (!EnumDisplayDevices(deviceName, 0, ref mon, EDD_GET_DEVICE_INTERFACE_NAME)) return false;
                // "\\?\DISPLAY#GSMC0C8#5&22b9b0df&0&UID4352#{guid}"
                string[] parts = (mon.DeviceID ?? "").Split('#');
                if (parts.Length < 3 || !parts[0].EndsWith("DISPLAY", StringComparison.OrdinalIgnoreCase)) return false;
                string hardwareId = parts[1];
                string instanceId = parts[2];
                if (hardwareId.Length == 0 || string.Equals(hardwareId, "Default_Monitor", StringComparison.OrdinalIgnoreCase)) return false;
                int uidAt = instanceId.LastIndexOf("UID", StringComparison.OrdinalIgnoreCase);
                identity = hardwareId + "-" + (uidAt >= 0 ? instanceId.Substring(uidAt) : instanceId);
                edid = ReadEdid(hardwareId, instanceId);
                edidName = EdidName(edid);
                return true;
            }
            catch { return false; }
        }

        static byte[] ReadEdid(string hardwareId, string instanceId)
        {
            try
            {
                string key = @"SYSTEM\CurrentControlSet\Enum\DISPLAY\" + hardwareId + "\\" + instanceId + @"\Device Parameters";
                using (RegistryKey k = Registry.LocalMachine.OpenSubKey(key))
                    return k == null ? null : k.GetValue("EDID") as byte[];
            }
            catch { return null; }
        }

        static string EdidName(byte[] edid)
        {
            if (edid == null || edid.Length < 126) return "";
            // Four 18-byte descriptors from byte 54; one starting 00 00 00 FC holds the
            // name, padded with 0x0A.
            for (int offset = 54; offset + 18 <= 126; offset += 18)
            {
                if (edid[offset] != 0 || edid[offset + 1] != 0 || edid[offset + 2] != 0 || edid[offset + 3] != 0xFC) continue;
                int length = 0;
                while (length < 13 && edid[offset + 5 + length] != 0x0A && edid[offset + 5 + length] != 0) length++;
                return System.Text.Encoding.ASCII.GetString(edid, offset + 5, length).Trim();
            }
            return "";
        }
    }
}
