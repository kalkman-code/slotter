using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Forms;
using System.Windows.Threading;

namespace Slotter
{
    // Manual drag-snap: while the active workspace's zones are live, dragging a
    // window's title bar shows every zone as an overlay and releasing inside one
    // snaps the window there. All Win32 interop and the zone-bounds maths carry over
    // from the WinForms build untouched.
    public class SnapEngine
    {
        [DllImport("user32")] static extern bool IsZoomed(IntPtr h);
        [DllImport("user32")] static extern bool IsIconic(IntPtr h);
        [DllImport("user32")] static extern bool ShowWindow(IntPtr h, int cmd);
        [DllImport("user32")] static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32")] static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
        [DllImport("user32")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
        [DllImport("user32")] static extern int GetWindowTextLength(IntPtr h);
        [DllImport("user32", CharSet = CharSet.Auto)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
        [DllImport("user32")] static extern int GetWindowLong(IntPtr h, int index);
        [DllImport("user32", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int max);
        delegate bool EnumProc(IntPtr h, IntPtr l);
        [DllImport("user32")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
        [DllImport("user32")] static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32", SetLastError = true)] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
        delegate void WinEventDelegate(IntPtr hook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint eventThread, uint eventTime);
        [DllImport("user32", SetLastError = true)] static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr module, WinEventDelegate callback, uint processId, uint threadId, uint flags);
        [DllImport("user32", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] static extern bool UnhookWinEvent(IntPtr hook);
        [DllImport("user32", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] static extern bool GetCursorPos(out POINT p);
        [DllImport("dwmapi")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int size);
        [DllImport("dwmapi")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);

        [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }

        class SnapTarget { public Rectangle Bounds; public string Label; }

        readonly Func<Profile> activeProfile;
        readonly Dispatcher dispatcher;
        IntPtr hook;
        WinEventDelegate events;
        GCHandle eventsRoot;
        readonly DispatcherTimer timeout;
        readonly DispatcherTimer retry;
        IntPtr movingWindow;
        uint movingStartedAt;
        long generation;
        IntPtr retryHwnd;
        Rectangle retryBounds;
        int retryAttempts;
        readonly List<SnapTarget> targets = new List<SnapTarget>();
        readonly List<SnapOverlay> overlays = new List<SnapOverlay>();
        // The move-size events say only when a drag starts and ends, so the zone under the
        // cursor is found by polling while the overlays are up.
        readonly DispatcherTimer track;

        public SnapEngine(Func<Profile> activeProfile)
        {
            this.activeProfile = activeProfile;
            dispatcher = System.Windows.Application.Current.Dispatcher;
            timeout = new DispatcherTimer { Interval = TimeSpan.FromSeconds(15) };
            timeout.Tick += delegate { CloseTargets(); };
            retry = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(150) };
            retry.Tick += delegate { RetrySnap(); };
            track = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(40) };
            track.Tick += delegate { LightTarget(); };
        }

        void LightTarget()
        {
            System.Drawing.Point cursor;
            if (!TryGetCursor(out cursor)) return;
            int hit = -1;
            for (int i = targets.Count - 1; i >= 0; i--)
                if (targets[i].Bounds.Contains(cursor)) { hit = i; break; }
            for (int i = 0; i < overlays.Count; i++) overlays[i].Lit = i == hit;
        }

        public void Start()
        {
            events = OnWindowMoveEvent;
            eventsRoot = GCHandle.Alloc(events);
            hook = SetWinEventHook(0x000A, 0x000B, IntPtr.Zero, events, 0, 0, 0x0002);
            if (hook == IntPtr.Zero)
            {
                Log.Write("manual snap hook could not start: " + Marshal.GetLastWin32Error());
                eventsRoot.Free();
            }
        }

        public void Stop()
        {
            if (hook != IntPtr.Zero) UnhookWinEvent(hook);
            hook = IntPtr.Zero;
            CloseTargets();
            if (eventsRoot.IsAllocated) eventsRoot.Free();
            timeout.Stop();
            retry.Stop();
            track.Stop();
        }

        public void CloseTargets()
        {
            timeout.Stop();
            track.Stop();
            retry.Stop();
            retryHwnd = IntPtr.Zero;
            retryAttempts = 0;
            foreach (SnapOverlay overlay in overlays)
            {
                try { overlay.Close(); }
                catch { }
            }
            overlays.Clear();
            targets.Clear();
            movingWindow = IntPtr.Zero;
            movingStartedAt = 0;
            generation++;
        }

        void OnWindowMoveEvent(IntPtr hookHandle, uint eventType, IntPtr hwnd, int idObject, int idChild, uint eventThread, uint eventTime)
        {
            if (hwnd == IntPtr.Zero || idObject != 0 || idChild != 0) return;
            try
            {
                dispatcher.BeginInvoke(new Action(delegate
                {
                    if (eventType == 0x000A) OpenTargets(hwnd, eventTime);
                    else if (eventType == 0x000B) ApplyTarget(hwnd, eventTime);
                }));
            }
            catch { }
        }

        void OpenTargets(IntPtr hwnd, uint eventTime)
        {
            CloseTargets();
            int pid;
            if (!IsUserWindow(hwnd, Process.GetCurrentProcess().Id, out pid)) return;
            RECT rect;
            if (!GetWindowRect(hwnd, out rect)) return;
            System.Drawing.Point cursor;
            if (!TryGetCursor(out cursor)) return;
            int titleBand = Math.Max(48, SystemInformation.CaptionHeight * 2);
            int resizeInset = Math.Max(4, SystemInformation.FrameBorderSize.Height);
            if (cursor.X < rect.Left + resizeInset || cursor.X > rect.Right - resizeInset || cursor.Y < rect.Top + resizeInset || cursor.Y > rect.Top + titleBand) return;
            Profile profile = activeProfile();
            if (profile == null || profile.Zones.Count == 0) return;
            movingWindow = hwnd;
            movingStartedAt = eventTime;
            generation++;
            Screen[] screens = Screen.AllScreens;
            for (int i = 0; i < profile.Zones.Count; i++)
            {
                Zone zone = profile.Zones[i];
                // A zone on a disconnected monitor would fall back to monitor 1 and
                // shadow the real zones there - leave it out of the drag targets.
                if (Config.ResolveScreenIndex(zone, screens) < 0) continue;
                string label = (i + 1) + "  " + (string.IsNullOrEmpty(zone.Prog) ? "Empty" : zone.Prog);
                Rectangle bounds = ZoneBounds(zone);
                targets.Add(new SnapTarget { Bounds = bounds, Label = label });
                SnapOverlay overlay = new SnapOverlay(bounds, label);
                overlays.Add(overlay);
                overlay.Show();
            }
            timeout.Stop();
            timeout.Start();
            LightTarget();
            track.Start();
        }

        void ApplyTarget(IntPtr hwnd, uint eventTime)
        {
            if (hwnd != movingWindow || generation == 0 || unchecked((int)(eventTime - movingStartedAt)) < 0) return;
            Rectangle? target = null;
            int pid;
            try
            {
                System.Drawing.Point cursor;
                if (!IsUserWindow(hwnd, Process.GetCurrentProcess().Id, out pid) || !TryGetCursor(out cursor)) return;
                for (int i = targets.Count - 1; i >= 0; i--)
                    if (targets[i].Bounds.Contains(cursor)) { target = targets[i].Bounds; break; }
            }
            finally { CloseTargets(); }
            if (target.HasValue && IsUserWindow(hwnd, Process.GetCurrentProcess().Id, out pid) && !MoveToBounds(hwnd, target.Value))
            {
                // The move loop has not fully released the window yet - retry until it has.
                retryHwnd = hwnd;
                retryBounds = target.Value;
                retryAttempts = 0;
                retry.Stop();
                retry.Start();
            }
        }

        void RetrySnap()
        {
            retryAttempts++;
            if (MoveToBounds(retryHwnd, retryBounds) || retryAttempts >= 8) retry.Stop();
        }

        static bool TryGetCursor(out System.Drawing.Point cursor)
        {
            POINT raw;
            if (GetCursorPos(out raw)) { cursor = new System.Drawing.Point(raw.X, raw.Y); return true; }
            cursor = System.Drawing.Point.Empty;
            return false;
        }

        public static Rectangle ZoneBounds(Zone z)
        {
            Screen[] screens = Screen.AllScreens;
            int idx = Config.ResolveScreenIndex(z, screens);
            if (idx < 0) idx = 0;
            Rectangle wa = screens[idx].WorkingArea;
            return new Rectangle(
                wa.Left + (int)Math.Round(z.X * wa.Width / 100.0),
                wa.Top + (int)Math.Round(z.Y * wa.Height / 100.0),
                Math.Max(1, (int)Math.Round(z.W * wa.Width / 100.0)),
                Math.Max(1, (int)Math.Round(z.H * wa.Height / 100.0)));
        }

        // DisplayFusion-style: compensate for the invisible DWM resize border so the
        // visible window edges land exactly on the zone (raw MoveWindow leaves a gap).
        public static bool MoveToZone(IntPtr hwnd, Zone z) { return MoveToBounds(hwnd, ZoneBounds(z)); }

        public static bool MoveToBounds(IntPtr hwnd, Rectangle target)
        {
            if (IsZoomed(hwnd) || IsIconic(hwnd)) ShowWindow(hwnd, 9); // SW_RESTORE before sizing

            int tx = target.Left, ty = target.Top, tw = target.Width, th = target.Height;

            RECT wr, fr;
            if (GetWindowRect(hwnd, out wr) && DwmGetWindowAttribute(hwnd, 9, out fr, Marshal.SizeOf(typeof(RECT))) == 0)
            {
                int ml = fr.Left - wr.Left, mt = fr.Top - wr.Top, mr = wr.Right - fr.Right, mb = wr.Bottom - fr.Bottom;
                tx -= ml; ty -= mt; tw += ml + mr; th += mt + mb;
            }
            bool moved = SetWindowPos(hwnd, IntPtr.Zero, tx, ty, tw, th, 0x0004 | 0x0010); // SWP_NOZORDER | SWP_NOACTIVATE
            int wpid; GetWindowThreadProcessId(hwnd, out wpid);
            if (!moved) Log.Write("snap failed: " + Marshal.GetLastWin32Error() + " [pid " + wpid + " \"" + WindowTitle(hwnd) + "\"]");
            else Log.Write("snapped \"" + WindowTitle(hwnd) + "\" -> " + target);
            return moved;
        }

        public static string WindowTitle(IntPtr hwnd)
        {
            StringBuilder sb = new StringBuilder(128);
            GetWindowText(hwnd, sb, sb.Capacity);
            return sb.ToString();
        }

        public static bool IsUserWindow(IntPtr h, int self, out int pid)
        {
            pid = 0;
            if (!IsWindowVisible(h) || GetWindow(h, 4) != IntPtr.Zero || GetWindowTextLength(h) == 0) return false;
            if ((GetWindowLong(h, -20) & 0x00000080) != 0) return false;
            int cloaked;
            if (DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return false;
            GetWindowThreadProcessId(h, out pid);
            if (pid == self) return false;
            StringBuilder sb = new StringBuilder(64);
            GetClassName(h, sb, sb.Capacity);
            string cls = sb.ToString();
            return cls != "Shell_TrayWnd" && cls != "Shell_SecondaryTrayWnd" && cls != "Progman" && cls != "WorkerW";
        }

        // Top-level user application windows (not the shell, tray, owned dialogs, or Slotter).
        public static List<IntPtr> UserWindows()
        {
            int self = Process.GetCurrentProcess().Id;
            List<IntPtr> res = new List<IntPtr>();
            EnumWindows(delegate(IntPtr h, IntPtr l)
            {
                int pid;
                if (!IsUserWindow(h, self, out pid)) return true;
                res.Add(h);
                return true;
            }, IntPtr.Zero);
            return res;
        }

        public static HashSet<IntPtr> WindowsOf(params string[] exeNames)
        {
            HashSet<int> pids = new HashSet<int>();
            foreach (string name in exeNames)
                foreach (Process pr in Process.GetProcessesByName(name)) { pids.Add(pr.Id); pr.Dispose(); }
            HashSet<IntPtr> set = new HashSet<IntPtr>();
            int self = Process.GetCurrentProcess().Id;
            EnumWindows(delegate(IntPtr h, IntPtr l)
            {
                int pid;
                if (IsUserWindow(h, self, out pid) && pids.Contains(pid)) set.Add(h);
                return true;
            }, IntPtr.Zero);
            return set;
        }
    }
}
