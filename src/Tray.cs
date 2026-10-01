using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using Forms = System.Windows.Forms;

namespace Slotter
{
    // The notification-area icon and its menu. WPF has no tray API, so the icon is a WinForms
    // NotifyIcon; the menu is a WPF ContextMenu in the design's own shape. Left click opens
    // the designer, right click the menu.
    public sealed class Tray : IDisposable
    {
        readonly Forms.NotifyIcon icon;
        readonly IntPtr owner;

        // Rebuilt on every open, because the menu shows live state.
        public event EventHandler Opening;
        public ContextMenu Menu { get; private set; }
        public Action PrimaryAction { get; set; }

        // owner must be a top-level window of this process: Windows dismisses a popup only for
        // the foreground process, so without foregrounding it the menu stays after a click
        // elsewhere.
        public Tray(System.Drawing.Icon trayIcon, string tooltip, IntPtr owner)
        {
            this.owner = owner;
            Menu = new ContextMenu { Style = Ui.S("Menu"), StaysOpen = false };
            icon = new Forms.NotifyIcon { Icon = trayIcon, Text = tooltip };
            icon.MouseUp += OnMouseUp;
            icon.Visible = true;
        }

        void OnMouseUp(object sender, Forms.MouseEventArgs e)
        {
            if (e.Button != Forms.MouseButtons.Left && e.Button != Forms.MouseButtons.Right) return;
            Application app = Application.Current;
            if (app == null) return;
            Action action = e.Button == Forms.MouseButtons.Left && PrimaryAction != null ? PrimaryAction : (Action)Show;
            app.Dispatcher.BeginInvoke(action);
        }

        void Show()
        {
            EventHandler handler = Opening;
            if (handler != null) handler(this, EventArgs.Empty);
            if (Menu.Items.Count == 0) return;
            if (owner != IntPtr.Zero) SetForegroundWindow(owner);
            Menu.Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint;
            Menu.IsOpen = true;
        }

        public static MenuItem Header(string text) { return new MenuItem { Header = text, Style = Ui.S("Menu.Header") }; }
        public static MenuItem Caption(string text) { return new MenuItem { Header = text.ToUpperInvariant(), Style = Ui.S("Menu.Caption") }; }
        public static Separator Rule() { return new Separator { Style = Ui.S("Menu.Rule") }; }

        public static MenuItem Item(string text, string note, RoutedEventHandler click)
        {
            MenuItem item = new MenuItem { Header = text, Style = Ui.S("Menu.TrayItem") };
            if (!string.IsNullOrEmpty(note)) item.InputGestureText = note;
            if (click != null) item.Click += click;
            return item;
        }

        public static MenuItem Toggle(string text, bool on, RoutedEventHandler click)
        {
            MenuItem item = Item(text, null, click);
            item.IsCheckable = true;
            item.IsChecked = on;
            return item;
        }

        public void Dispose()
        {
            try
            {
                icon.Visible = false;
                icon.Dispose();
            }
            catch { }
        }

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool SetForegroundWindow(IntPtr hWnd);
    }
}
