using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;

namespace Slotter
{
    // The full-screen zone highlight shown while dragging a window's title bar. Drawn
    // vector rather than GDI, so it is correct at any DPI with no manual scaling.
    // Click-through and never-activate: dragging must keep controlling the window
    // underneath, not this overlay.
    //
    // Placed by a direct SetWindowPos with the same physical-pixel Rectangle every
    // other snap target uses, rather than through WPF's Left/Top (which are DIPs
    // relative to a DPI context WPF cannot know until the HWND already has a
    // monitor). That is the one thing today's DPI fixes never touched: this class
    // used to derive from plain Form, so it is the surface most likely to be wrong on
    // a mixed-DPI multi-monitor desk, and a wrong DIP-to-pixel guess here would
    // silently reproduce that.
    public sealed class SnapOverlay : Window
    {
        const int GWL_EXSTYLE = -20;
        const int WS_EX_TRANSPARENT = 0x00000020;
        const int WS_EX_TOOLWINDOW = 0x00000080;
        const int WS_EX_NOACTIVATE = 0x08000000;
        const uint SWP_NOACTIVATE = 0x0010;
        const uint SWP_NOZORDER = 0x0004;

        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hwnd, int index);
        [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hwnd, int index, int value);
        [DllImport("user32.dll", SetLastError = true)] static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);

        readonly System.Drawing.Rectangle bounds;
        readonly Border outline, chip;
        readonly TextBlock text;

        public SnapOverlay(System.Drawing.Rectangle bounds, string label)
        {
            this.bounds = bounds;
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            ShowActivated = false;
            ShowInTaskbar = false;
            Topmost = true;
            ResizeMode = ResizeMode.NoResize;
            Background = System.Windows.Media.Brushes.Transparent;
            WindowStartupLocation = WindowStartupLocation.Manual;
            FontFamily = Ui.UiFont;
            UseLayoutRounding = true;
            Content = Build(label, out outline, out chip, out text);
        }

        // Drawn on the real screen with no bezel art: the desktop dimmed, each zone an outline
        // with its number and app, and the zone under the cursor filled and thickened, so it
        // reads without the colour.
        public static Grid Build(string label, out Border outline, out Border chip, out TextBlock text)
        {
            Grid root = new Grid();
            root.Children.Add(new Border { Background = Ui.B("B.OverlayDim") });
            outline = new Border { Margin = new Thickness(4), CornerRadius = new CornerRadius(3) };
            root.Children.Add(outline);
            text = new TextBlock { Text = label, FontSize = 16, FontWeight = FontWeights.ExtraBold, TextTrimming = TextTrimming.CharacterEllipsis };
            chip = new Border
            {
                HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(14),
                CornerRadius = new CornerRadius(3), Padding = new Thickness(8, 3, 8, 4), Child = text
            };
            root.Children.Add(chip);
            Paint(false, outline, chip, text);
            return root;
        }

        public static void Paint(bool lit, Border outline, Border chip, TextBlock text)
        {
            outline.BorderThickness = new Thickness(lit ? 3 : 2);
            outline.BorderBrush = Ui.B(lit ? "B.Selection" : "B.OverlayLine");
            outline.Background = lit ? Ui.B("B.OverlayLit") : null;
            chip.Background = Ui.B(lit ? "B.Selection" : "B.Zone");
            text.Foreground = Ui.B(lit ? "B.SelectionInk" : "B.Ink");
        }

        bool lit;
        public bool Lit
        {
            get { return lit; }
            set { if (value == lit) return; lit = value; Paint(value, outline, chip, text); }
        }

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            IntPtr hwnd = new WindowInteropHelper(this).Handle;
            int style = GetWindowLong(hwnd, GWL_EXSTYLE);
            SetWindowLong(hwnd, GWL_EXSTYLE, style | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
            SetWindowPos(hwnd, IntPtr.Zero, bounds.X, bounds.Y, bounds.Width, bounds.Height, SWP_NOZORDER | SWP_NOACTIVATE);
        }
    }
}
