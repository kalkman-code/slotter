using System;
using System.Diagnostics;
using System.IO;
using System.Security.Principal;

namespace Snappy
{
    // Where Snappy shows up outside its own window, and the elevation it needs to get
    // there. Snappy must run elevated to snap elevated windows (UIPI denies
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
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "Snappy.lnk"); }
        }

        static void RunSchtasks(string args)
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
                    if (p.ExitCode != 0) Log.Write("schtasks failed (" + p.ExitCode + "): " + err.Trim());
                }
            }
            catch (Exception ex) { Log.Write("schtasks: " + ex.Message); }
        }

        static void EnsureStartup()
        {
            try { if (File.Exists(StartupLnk)) File.Delete(StartupLnk); }
            catch (Exception ex) { Log.Write("remove startup lnk: " + ex.Message); }
            string exe = Process.GetCurrentProcess().MainModule.FileName;
            RunSchtasks("/Create /TN Snappy /TR \"\\\"" + exe + "\\\"\" /SC ONLOGON /RL HIGHEST /F");
        }

        public static void ApplyStartupSetting(bool startWithWindows)
        {
            if (startWithWindows) EnsureStartup();
            else RunSchtasks("/Delete /TN Snappy /F");
        }
    }
}
