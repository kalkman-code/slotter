using System;
using System.Diagnostics;
using System.IO;
using System.Security.Principal;

namespace Slotter
{
    // Where Slotter shows up outside its own window, and the elevation it needs to get
    // there. Slotter must run elevated to snap elevated windows (UIPI denies
    // SetWindowPos upward), so "start with Windows" is a highest-run-level logon task
    // rather than a shell:startup shortcut, which would come up Medium and silently
    // lose that ability.
    public static class Presence
    {
        public static bool IsElevated()
        {
            using (WindowsIdentity id = WindowsIdentity.GetCurrent())
                return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
        }

        static string StartupLnk
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "Slotter.lnk"); }
        }

        static int RunSchtasks(string args, bool quiet = false)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo("schtasks.exe", args)
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                using (Process p = Process.Start(psi))
                {
                    string err = p.StandardError.ReadToEnd();
                    p.WaitForExit();
                    if (p.ExitCode != 0 && !quiet) Log.Write("schtasks failed (" + p.ExitCode + "): " + err.Trim());
                    return p.ExitCode;
                }
            }
            catch (Exception ex) { Log.Write("schtasks: " + ex.Message); return -1; }
        }

        // Slotter was called Snappy before 1.0. Its logon task and shortcut would start
        // the old executable next to this one, so they go the first time Slotter runs.
        public static void RetireSnappy()
        {
            if (RunSchtasks("/Query /TN Snappy", true) == 0) RunSchtasks("/Delete /TN Snappy /F");
            string lnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "Snappy.lnk");
            try { if (File.Exists(lnk)) File.Delete(lnk); }
            catch (Exception ex) { Log.Write("remove Snappy startup lnk: " + ex.Message); }
        }

        static void EnsureStartup()
        {
            try { if (File.Exists(StartupLnk)) File.Delete(StartupLnk); }
            catch (Exception ex) { Log.Write("remove startup lnk: " + ex.Message); }
            string exe = Process.GetCurrentProcess().MainModule.FileName;
            RunSchtasks("/Create /TN Slotter /TR \"\\\"" + exe + "\\\"\" /SC ONLOGON /RL HIGHEST /F");
        }

        public static void ApplyStartupSetting(bool startWithWindows)
        {
            if (startWithWindows) EnsureStartup();
            else RunSchtasks("/Delete /TN Slotter /F");
        }
    }
}
