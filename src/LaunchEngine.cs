using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace Slotter
{
    // Opens a workspace's programs and places each into its zone. Runs on a
    // background thread; the caller marshals the result back to the UI thread.
    public static class LaunchEngine
    {
        [DllImport("user32")] static extern bool AllowSetForegroundWindow(int pid);
        [DllImport("user32")] static extern bool IsWindowVisible(IntPtr h);

        static readonly HashSet<string> ShellExeNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "pwsh", "powershell", "cmd", "wt" };

        public static LaunchResult LaunchApps(Profile p, List<ProgItem> lib)
        {
            LaunchResult result = new LaunchResult();
            Screen[] screens = Screen.AllScreens;
            foreach (Zone z in p.Zones)
            {
                if (!string.IsNullOrEmpty(z.PlateId)) continue;
                if (string.IsNullOrEmpty(z.Prog)) continue;
                if (Config.ResolveScreenIndex(z, screens) < 0) { Log.Write("skip " + z.Prog + ": monitor " + z.Mon + " disconnected"); continue; }
                result.Planned++;
                try
                {
                    ProgItem prog = null;
                    foreach (ProgItem pi in lib) if (string.Equals(pi.Name, z.Prog, StringComparison.OrdinalIgnoreCase)) { prog = pi; break; }
                    if (prog == null || string.IsNullOrEmpty(prog.Exe))
                    {
                        string error = "'" + z.Prog + "' is missing from Programs.";
                        Log.Write(error); if (result.FirstError == null) result.FirstError = error; continue;
                    }

                    string exe = prog.Exe.Trim();
                    string args = prog.Args ?? "";
                    if (exe.Length >= 2 && exe[0] == '"' && exe[exe.Length - 1] == '"') exe = exe.Substring(1, exe.Length - 2); // tolerate a quoted path
                    if (exe.ToLowerInvariant().EndsWith(".lnk")) ResolveLnk(ref exe, ref args); // resolve shortcut -> real target so it tiles

                    string exeName = Path.GetFileNameWithoutExtension(exe);
                    string[] watchNames = ShellExeNames.Contains(exeName) ? new[] { exeName, "WindowsTerminal" } : new[] { exeName };
                    HashSet<IntPtr> before = SnapEngine.WindowsOf(watchNames);
                    Process started = Process.Start(new ProcessStartInfo(exe, args) { UseShellExecute = true });
                    if (started != null)
                    {
                        // We launch from a background thread, which Windows does not treat as
                        // the foreground process - without this grant, the new window can come
                        // up minimized/inactive and reject SetWindowPos (ERROR_ACCESS_DENIED).
                        try { AllowSetForegroundWindow(started.Id); } catch { }
                        started.Dispose();
                    }

                    // Poll for a window that did not exist before launch - survives
                    // Chrome/VS Code-style handoff, and lets N identical exes each grab their
                    // own new window in turn.
                    IntPtr hwnd = IntPtr.Zero;
                    for (int i = 0; i < 50 && hwnd == IntPtr.Zero; i++)
                    {
                        Thread.Sleep(100);
                        foreach (IntPtr w in SnapEngine.WindowsOf(watchNames))
                            if (!before.Contains(w)) { hwnd = w; break; }
                    }
                    if (hwnd == IntPtr.Zero)
                    {
                        string error = "No new " + exeName + " window appeared.";
                        Log.Write(error); if (result.FirstError == null) result.FirstError = error; continue;
                    }
                    Thread.Sleep(400); // let the window finish creating before we move it
                    bool moved = SnapEngine.MoveToZone(hwnd, z);
                    Thread.Sleep(500);
                    if (!moved || !IsWindowVisible(hwnd))
                        foreach (IntPtr w in SnapEngine.WindowsOf(watchNames))
                            if (!before.Contains(w)) { hwnd = w; break; }
                    moved = SnapEngine.MoveToZone(hwnd, z) || moved; // re-apply - terminals/Electron often self-resize just after launch
                    if (moved) result.Placed++;
                    else if (result.FirstError == null) result.FirstError = "Windows could not move " + exeName + ".";
                }
                catch (Exception ex)
                {
                    Log.Write("launch " + z.Prog + ": " + ex.Message);
                    if (result.FirstError == null) result.FirstError = ex.Message;
                }
            }
            return result;
        }

        // Read a .lnk shortcut's real target exe + args so the launched window can be
        // found and tiled.
        static void ResolveLnk(ref string exe, ref string args)
        {
            try
            {
                dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
                dynamic sc = shell.CreateShortcut(exe);
                string target = sc.TargetPath;
                if (!string.IsNullOrEmpty(target))
                {
                    if (string.IsNullOrEmpty(args)) args = sc.Arguments; // shortcut's own args, unless the library overrides
                    exe = target;
                }
            }
            catch (Exception ex) { Log.Write("resolve lnk: " + ex.Message); }
        }

        // Politely ask every app window to close (WM_CLOSE). Apps with unsaved work
        // show their own prompt and stay - we post and move on, never blocking.
        [DllImport("user32")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr wp, IntPtr lp);
        [DllImport("user32")] static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);

        public static int CloseAllWindows()
        {
            try
            {
                List<IntPtr> windows = SnapEngine.UserWindows();
                foreach (IntPtr h in windows) PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero);
                return windows.Count;
            }
            catch (Exception ex) { Log.Write("close all: " + ex.Message); }
            return 0;
        }

        // Hard-terminate every process that owns a user window - except the shell and Slotter.
        public static int ForceKillAll(List<IntPtr> windows)
        {
            int self = Process.GetCurrentProcess().Id;
            HashSet<int> pids = new HashSet<int>();
            foreach (IntPtr h in windows) { int pid; GetWindowThreadProcessId(h, out pid); pids.Add(pid); }
            int killed = 0;
            foreach (int pid in pids)
            {
                if (pid == self) continue;
                try
                {
                    Process p = Process.GetProcessById(pid);
                    if (string.Equals(p.ProcessName, "explorer", StringComparison.OrdinalIgnoreCase)) { p.Dispose(); continue; } // don't nuke the shell
                    p.Kill();
                    p.Dispose();
                    killed++;
                }
                catch (Exception ex) { Log.Write("kill " + pid + ": " + ex.Message); }
            }
            return killed;
        }
    }
}
