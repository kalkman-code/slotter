using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Threading;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;

namespace Slotter
{
    public sealed class DesktopSnapshot
    {
        public Guid? CurrentId;
        public readonly List<DesktopInfo> Desktops = new List<DesktopInfo>();
        public bool Available
        {
            get
            {
                if (!CurrentId.HasValue) return false;
                foreach (DesktopInfo desktop in Desktops) if (desktop.Id == CurrentId.Value) return true;
                return false;
            }
        }
    }

    public sealed class DesktopInfo
    {
        public Guid Id;
        public string Name;
    }

    public sealed class VirtualDesktops : IDisposable
    {
        const string Path = @"Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops";
        const uint NotifyChangeName = 1, NotifyChangeLastSet = 4, WaitObject0 = 0;
        [DllImport("advapi32.dll", SetLastError = true)] static extern int RegNotifyChangeKeyValue(SafeRegistryHandle key, bool subtree, uint filter, IntPtr eventHandle, bool asynchronous);
        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateEvent(IntPtr attributes, bool manualReset, bool initialState, string name);
        [DllImport("kernel32.dll", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool ResetEvent(IntPtr handle);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool CloseHandle(IntPtr handle);

        readonly Dispatcher dispatcher;
        readonly Thread watcher;
        volatile bool stopped;
        public event Action<DesktopSnapshot> Changed;
        public DesktopSnapshot Current { get; private set; }

        public VirtualDesktops(Dispatcher dispatcher)
        {
            this.dispatcher = dispatcher;
            Current = Read();
            watcher = new Thread(Watch) { IsBackground = true, Name = "Slotter virtual desktop watcher" };
            watcher.Start();
        }

        static DesktopSnapshot Read()
        {
            DesktopSnapshot result = new DesktopSnapshot();
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(Path, false))
                {
                    if (key == null) return result;
                    result.CurrentId = ReadGuid(key.GetValue("CurrentVirtualDesktop"));
                    byte[] ids = key.GetValue("VirtualDesktopIDs") as byte[];
                    if (ids != null)
                    {
                        for (int i = 0; i + 16 <= ids.Length; i += 16)
                        {
                            byte[] bytes = new byte[16];
                            Array.Copy(ids, i, bytes, 0, 16);
                            Guid id = new Guid(bytes);
                            string name = "";
                            using (RegistryKey desktops = key.OpenSubKey("Desktops\\{" + id.ToString() + "}", false))
                                if (desktops != null) name = Convert.ToString(desktops.GetValue("Name")) ?? "";
                            result.Desktops.Add(new DesktopInfo { Id = id, Name = name });
                        }
                    }
                }
            }
            catch (Exception ex) { Log.Write("desktop detection: " + ex.Message); }
            return result;
        }

        static Guid? ReadGuid(object value)
        {
            byte[] bytes = value as byte[];
            if (bytes != null && bytes.Length == 16) return new Guid(bytes);
            Guid parsed;
            return Guid.TryParse(Convert.ToString(value), out parsed) ? (Guid?)parsed : null;
        }

        void Watch()
        {
            while (!stopped)
            {
                try
                {
                    using (RegistryKey key = Registry.CurrentUser.OpenSubKey(Path, false))
                    {
                        if (key == null) { Thread.Sleep(300); Publish(Read()); continue; }
                        IntPtr signal = CreateEvent(IntPtr.Zero, true, false, null);
                        if (signal == IntPtr.Zero) { Thread.Sleep(1000); continue; }
                        try
                        {
                            while (!stopped)
                            {
                                int error = RegNotifyChangeKeyValue(key.Handle, true, NotifyChangeName | NotifyChangeLastSet, signal, true);
                                if (error != 0) break;
                                uint wait;
                                do
                                {
                                    wait = WaitForSingleObject(signal, 1000);
                                }
                                while (!stopped && wait == 0x102);
                                if (stopped) break;
                                if (wait != WaitObject0) { Thread.Sleep(500); break; }
                                ResetEvent(signal);
                                Publish(ReadWithRetry());
                            }
                        }
                        finally { CloseHandle(signal); }
                    }
                }
                catch (Exception ex) { Log.Write("desktop watcher: " + ex.Message); Thread.Sleep(1000); }
            }
        }

        void Publish(DesktopSnapshot snapshot)
        {
            if (stopped) return;
            dispatcher.BeginInvoke(new Action(delegate
            {
                if (Equivalent(Current, snapshot)) return;
                Current = snapshot;
                Action<DesktopSnapshot> changed = Changed;
                if (changed != null) changed(snapshot);
            }));
        }

        static DesktopSnapshot ReadWithRetry()
        {
            DesktopSnapshot snapshot = Read();
            for (int i = 0; i < 5 && !snapshot.Available; i++)
            {
                Thread.Sleep(120);
                snapshot = Read();
            }
            return snapshot;
        }

        static bool Equivalent(DesktopSnapshot left, DesktopSnapshot right)
        {
            if (left == null || right == null || left.CurrentId != right.CurrentId || left.Desktops.Count != right.Desktops.Count) return false;
            for (int i = 0; i < left.Desktops.Count; i++)
                if (left.Desktops[i].Id != right.Desktops[i].Id || left.Desktops[i].Name != right.Desktops[i].Name) return false;
            return true;
        }

        public void Dispose()
        {
            stopped = true;
            if (watcher.IsAlive) watcher.Join(1200);
        }
    }
}
