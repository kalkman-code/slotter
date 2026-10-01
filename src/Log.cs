using System;
using System.Diagnostics;
using System.IO;

namespace Slotter
{
    public static class Log
    {
        public static readonly string Directory = AppContext.BaseDirectory;
        static readonly string Path = System.IO.Path.Combine(Directory, "slotter.log");

        public static void Write(string message)
        {
            Debug.WriteLine("Slotter: " + message);
            try { File.AppendAllText(Path, DateTime.Now.ToString("HH:mm:ss.fff") + " " + message + Environment.NewLine); }
            catch { }
        }
    }
}
