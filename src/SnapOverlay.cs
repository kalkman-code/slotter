using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;

namespace Snappy
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

            Grid root = new Grid();

            Border wash = new Border { CornerRadius = new CornerRadius(4), Opacity = 0.82 };
            wash.SetResourceReference(Border.BackgroundProperty, "ChromeBrush");
            root.Children.Add(wash);

            Border frame = new Border { BorderThickness = new Thickness(2), CornerRadius = new CornerRadius(4), Margin = new Thickness(1) };
            frame.SetResourceReference(Border.BorderBrushProperty, "AccentBrush");
            root.Children.Add(frame);

            Canvas corners = new Canvas();
            root.Children.Add(corners);
            SizeChanged += delegate { DrawCorners(corners); };

            TextBlock text = new TextBlock
            {
                Text = label.ToUpperInvariant(),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                TextAlignment = TextAlignment.Center,
                TextTrimming = TextTrimming.CharacterEllipsis,
                Margin = new Thickness(24)
            };
            text.SetResourceReference(FrameworkElement.StyleProperty, "Desk.Text.InspectorHeading");
            root.Children.Add(text);

            Content = root;
        }

        static void DrawCorners(Canvas corners)
        {
            corners.Children.Clear();
            double w = corners.ActualWidth, h = corners.ActualHeight;
            if (w <= 0 || h <= 0) return;
            double length = Math.Max(4, Math.Min(24, Math.Min(w, h) / 6));
            AddCorner(corners, 1, 1, length, 0, 0, length);
            AddCorner(corners, w - 1, 1, -length, 0, 0, length);
            AddCorner(corners, 1, h - 1, length, 0, 0, -length);
            AddCorner(corners, w - 1, h - 1, -length, 0, 0, -length);
        }

        static void AddCorner(Canvas host, double x, double y, double dx1, double dy1, double dx2, double dy2)
        {
            Path path = new Path { StrokeThickness = 3, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
            path.SetResourceReference(Shape.StrokeProperty, "AccentBrush");
            PathFigure figure = new PathFigure { StartPoint = new System.Windows.Point(x + dx1, y + dy1) };
            figure.Segments.Add(new LineSegment(new System.Windows.Point(x, y), true));
            figure.Segments.Add(new LineSegment(new System.Windows.Point(x + dx2, y + dy2), true));
            PathGeometry geometry = new PathGeometry();
            geometry.Figures.Add(figure);
            path.Data = geometry;
            host.Children.Add(path);
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
