using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Forms;

namespace Slotter
{
    public static class KeySnap
    {
        [DllImport("user32")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32")] static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out int pid);
        [DllImport("user32")] static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder name, int max);
        [DllImport("user32")] static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
        [DllImport("dwmapi")] static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out RECT rect, int size);

        [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
        sealed class PreviousFrame { public int ProcessId; public Rectangle Bounds; }
        static readonly Dictionary<IntPtr, PreviousFrame> previous = new Dictionary<IntPtr, PreviousFrame>();

        public static bool Perform(SnapAction action)
        {
            IntPtr hwnd = GetForegroundWindow();
            if (hwnd == IntPtr.Zero || !Eligible(hwnd)) return false;
            int pid;
            GetWindowThreadProcessId(hwnd, out pid);
            Rectangle current = VisibleBounds(hwnd);
            Screen screen = Screen.FromRectangle(current);
            Rectangle work = screen.WorkingArea;
            Rectangle target;
            if (action == SnapAction.Restore)
            {
                PreviousFrame saved;
                if (!previous.TryGetValue(hwnd, out saved)) return false;
                if (!IsWindow(hwnd) || saved.ProcessId != pid) { previous.Remove(hwnd); return false; }
                target = saved.Bounds;
                if (!SnapEngine.MoveToBounds(hwnd, target)) return false;
                previous.Remove(hwnd);
                return true;
            }
            if (action == SnapAction.NextDisplay || action == SnapAction.PreviousDisplay)
            {
                Screen[] screens = Screen.AllScreens;
                if (screens.Length == 0) return false;
                int index = Array.IndexOf(screens, screen);
                if (index < 0) return false;
                int step = action == SnapAction.NextDisplay ? 1 : -1;
                Screen destination = screens[(index + step + screens.Length) % screens.Length];
                target = Transfer(current, work, destination.WorkingArea);
            }
            else target = Frame(action, work, current);

            if (!previous.ContainsKey(hwnd) || previous[hwnd].ProcessId != pid)
                previous[hwnd] = new PreviousFrame { ProcessId = pid, Bounds = current };
            return SnapEngine.MoveToBounds(hwnd, target);
        }

        static bool Eligible(IntPtr hwnd)
        {
            if (!IsWindowVisible(hwnd)) return false;
            foreach (Window window in System.Windows.Application.Current.Windows)
            {
                if (new WindowInteropHelper(window).Handle != hwnd) continue;
                if (window is SnapOverlay || window is Toast) return false;
            }
            StringBuilder cls = new StringBuilder(128);
            GetClassName(hwnd, cls, cls.Capacity);
            string name = cls.ToString();
            if (name == "Shell_TrayWnd" || name == "Shell_SecondaryTrayWnd" || name == "Progman" || name == "WorkerW") return false;
            return true;
        }

        static Rectangle VisibleBounds(IntPtr hwnd)
        {
            RECT rect, frame;
            if (DwmGetWindowAttribute(hwnd, 9, out frame, Marshal.SizeOf(typeof(RECT))) == 0)
                return Rectangle.FromLTRB(frame.Left, frame.Top, frame.Right, frame.Bottom);
            if (!GetWindowRect(hwnd, out rect)) return Rectangle.Empty;
            return Rectangle.FromLTRB(rect.Left, rect.Top, rect.Right, rect.Bottom);
        }

        static Rectangle Frame(SnapAction action, Rectangle work, Rectangle current)
        {
            int left = work.Left, top = work.Top, right = work.Right, bottom = work.Bottom;
            int halfW = work.Width / 2, halfH = work.Height / 2;
            switch (action)
            {
                case SnapAction.LeftHalf: right = left + halfW; break;
                case SnapAction.RightHalf: left += halfW; break;
                case SnapAction.TopHalf: bottom = top + halfH; break;
                case SnapAction.BottomHalf: top += halfH; break;
                case SnapAction.TopLeft: right = left + halfW; bottom = top + halfH; break;
                case SnapAction.TopRight: left += halfW; bottom = top + halfH; break;
                case SnapAction.BottomLeft: right = left + halfW; top += halfH; break;
                case SnapAction.BottomRight: left += halfW; top += halfH; break;
                case SnapAction.LeftThird: right = left + work.Width / 3; break;
                case SnapAction.CentreThird: left += work.Width / 3; right = work.Left + work.Width * 2 / 3; break;
                case SnapAction.RightThird: left = work.Left + work.Width * 2 / 3; break;
                case SnapAction.LeftTwoThirds: right = work.Left + work.Width * 2 / 3; break;
                case SnapAction.RightTwoThirds: left += work.Width / 3; break;
                case SnapAction.Maximise: break;
                case SnapAction.Centre:
                    left = work.Left + (work.Width - current.Width) / 2;
                    top = work.Top + (work.Height - current.Height) / 2;
                    right = left + current.Width; bottom = top + current.Height;
                    break;
                default: return current;
            }
            return Rectangle.FromLTRB(left, top, right, bottom);
        }

        static Rectangle Transfer(Rectangle frame, Rectangle source, Rectangle target)
        {
            double x = (frame.Left - source.Left) / (double)Math.Max(1, source.Width);
            double y = (frame.Top - source.Top) / (double)Math.Max(1, source.Height);
            double w = frame.Width / (double)Math.Max(1, source.Width);
            double h = frame.Height / (double)Math.Max(1, source.Height);
            return new Rectangle(target.Left + (int)Math.Round(x * target.Width), target.Top + (int)Math.Round(y * target.Height),
                Math.Max(1, (int)Math.Round(w * target.Width)), Math.Max(1, (int)Math.Round(h * target.Height)));
        }
    }
}
