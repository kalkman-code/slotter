using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;

namespace Slotter
{
    // A text field with an inline label, a suffix and a fault state, which is all the
    // design's fields need: the four position fields, the rename field and the program form.
    public class Field : TextBox
    {
        public static readonly DependencyProperty LabelProperty =
            DependencyProperty.Register("Label", typeof(string), typeof(Field), new PropertyMetadata(null, delegate (DependencyObject d, DependencyPropertyChangedEventArgs e) { ((Field)d).ShowParts(); }));
        public static readonly DependencyProperty SuffixProperty =
            DependencyProperty.Register("Suffix", typeof(string), typeof(Field), new PropertyMetadata(null, delegate (DependencyObject d, DependencyPropertyChangedEventArgs e) { ((Field)d).ShowParts(); }));
        public static readonly DependencyProperty LabelWidthProperty =
            DependencyProperty.Register("LabelWidth", typeof(double), typeof(Field), new PropertyMetadata(0.0));
        public static readonly DependencyProperty FaultedProperty =
            DependencyProperty.Register("Faulted", typeof(bool), typeof(Field), new PropertyMetadata(false));

        public string Label { get { return (string)GetValue(LabelProperty); } set { SetValue(LabelProperty, value); } }
        public string Suffix { get { return (string)GetValue(SuffixProperty); } set { SetValue(SuffixProperty, value); } }
        public double LabelWidth { get { return (double)GetValue(LabelWidthProperty); } set { SetValue(LabelWidthProperty, value); } }
        public bool Faulted { get { return (bool)GetValue(FaultedProperty); } set { SetValue(FaultedProperty, value); } }

        // An empty label or suffix takes no room. Done here rather than with a null trigger in
        // the template, which never matched and left an 11px gap before the text.
        public override void OnApplyTemplate()
        {
            base.OnApplyTemplate();
            ShowParts();
        }

        void ShowParts()
        {
            FrameworkElement label = GetTemplateChild("Lbl") as FrameworkElement, suffix = GetTemplateChild("Suf") as FrameworkElement;
            if (label != null) label.Visibility = string.IsNullOrEmpty(Label) ? Visibility.Collapsed : Visibility.Visible;
            if (suffix != null) suffix.Visibility = string.IsNullOrEmpty(Suffix) ? Visibility.Collapsed : Visibility.Visible;
        }
    }

    // Theme lookups and the handful of element shapes every surface repeats.
    public static class Ui
    {
        public static void Install(ResourceDictionary into)
        {
            into.MergedDictionaries.Add(new ResourceDictionary { Source = new Uri("pack://application:,,,/Slotter;component/src/Theme.xaml") });
        }

        public static object R(string key) { return Application.Current.FindResource(key); }
        public static Style S(string key) { return (Style)R(key); }
        public static Brush B(string key) { return (Brush)R(key); }
        public static Color C(string key) { return ((SolidColorBrush)R(key)).Color; }
        public static double D(string key) { return (double)R(key); }
        public static Geometry G(string key) { return (Geometry)R(key); }
        public static FontFamily UiFont { get { return (FontFamily)R("Font.UI"); } }
        public static FontFamily DisplayFont { get { return (FontFamily)R("Font.Display"); } }

        public static TextBlock Text(string text, double size, FontWeight weight, string brush)
        {
            TextBlock t = new TextBlock { Text = text, FontSize = size, FontWeight = weight, VerticalAlignment = VerticalAlignment.Center };
            if (brush != null) t.Foreground = B(brush);
            return t;
        }

        // Uppercase small label ("LAUNCHES", "THIS ZONE"). WPF has no letter-spacing, so the
        // design's 0.05em tracking is not reproduced.
        public static TextBlock Label(string text)
        {
            TextBlock t = Text(text.ToUpperInvariant(), D("T.Caption"), FontWeights.Normal, "B.Ink3");
            t.Margin = new Thickness(0, 0, 0, 6);
            return t;
        }

        public static Button Button(string style, object content, Action click, string id = null)
        {
            Button b = new Button { Style = S(style), Content = content };
            if (click != null) b.Click += delegate { click(); };
            if (id != null) System.Windows.Automation.AutomationProperties.SetAutomationId(b, id);
            return b;
        }

        // An icon drawn in the colour of the control it sits in.
        public static Path Icon(string geometry, double size, bool filled, double stroke = 1.4)
        {
            Path p = new Path { Data = G(geometry), Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center, SnapsToDevicePixels = true };
            Binding ink = new Binding("Foreground") { RelativeSource = new RelativeSource(RelativeSourceMode.FindAncestor, typeof(Control), 1) };
            if (filled) p.SetBinding(Shape.FillProperty, ink);
            else { p.SetBinding(Shape.StrokeProperty, ink); p.StrokeThickness = stroke; }
            return p;
        }

        public static Path Icon(string geometry, double size, bool filled, Brush brush, double stroke = 1.4)
        {
            Path p = new Path { Data = G(geometry), Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center, SnapsToDevicePixels = true };
            if (filled) p.Fill = brush; else { p.Stroke = brush; p.StrokeThickness = stroke; }
            return p;
        }

        public static StackPanel Row(double gap, params UIElement[] items)
        {
            StackPanel s = new StackPanel { Orientation = Orientation.Horizontal };
            for (int i = 0; i < items.Length; i++)
            {
                if (items[i] == null) continue;
                FrameworkElement f = items[i] as FrameworkElement;
                if (f != null && s.Children.Count > 0) f.Margin = new Thickness(gap, f.Margin.Top, f.Margin.Right, f.Margin.Bottom);
                s.Children.Add(items[i]);
            }
            return s;
        }

        // A dashed tag ("OFFLINE", "DISCONNECTED"): dashed so the state does not rest on colour.
        public static Grid Tag(string text)
        {
            Grid g = new Grid { VerticalAlignment = VerticalAlignment.Center, SnapsToDevicePixels = true };
            g.Children.Add(new Rectangle { Stroke = B("B.Ink3"), StrokeThickness = 1, StrokeDashArray = new DoubleCollection { 3, 2 }, RadiusX = 3, RadiusY = 3 });
            TextBlock t = Text(text.ToUpperInvariant(), D("T.Tag"), FontWeights.SemiBold, "B.Ink2");
            t.Margin = new Thickness(6, 1, 6, 1);
            g.Children.Add(t);
            return g;
        }

        public static Border Kbd(string text)
        {
            return new Border
            {
                Background = B("B.Field"), BorderBrush = B("B.FieldBorder"), BorderThickness = new Thickness(1, 1, 1, 2),
                CornerRadius = new CornerRadius(3), Padding = new Thickness(6, 1, 6, 1), HorizontalAlignment = HorizontalAlignment.Left,
                Child = Text(text, D("T.Small"), FontWeights.Bold, "B.Ink"), Margin = new Thickness(0, 3, 0, 3)
            };
        }

        public static void Detach(UIElement e)
        {
            DependencyObject parent = VisualTreeHelper.GetParent(e) ?? LogicalTreeHelper.GetParent(e);
            Panel panel = parent as Panel;
            if (panel != null) { panel.Children.Remove(e); return; }
            Decorator d = parent as Decorator;
            if (d != null) { d.Child = null; return; }
            ContentControl c = parent as ContentControl;
            if (c != null) c.Content = null;
        }

        // Windows 11 tints a standard title bar to the ground when asked, so the window keeps
        // native chrome and still reads as one surface.
        const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
        const int DWMWA_CAPTION_COLOR = 35;
        const int DWMWA_TEXT_COLOR = 36;

        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

        public static void TintTitleBar(Window w)
        {
            IntPtr h = new WindowInteropHelper(w).Handle;
            if (h == IntPtr.Zero) return;
            try
            {
                int dark = 1;
                DwmSetWindowAttribute(h, DWMWA_USE_IMMERSIVE_DARK_MODE, ref dark, sizeof(int));
                int caption = ColorRef(C("B.Ground"));
                DwmSetWindowAttribute(h, DWMWA_CAPTION_COLOR, ref caption, sizeof(int));
                int text = ColorRef(C("B.Ink2"));
                DwmSetWindowAttribute(h, DWMWA_TEXT_COLOR, ref text, sizeof(int));
            }
            catch (Exception ex) { Log.Write("title bar: " + ex.Message); }
        }

        static int ColorRef(Color c) { return c.R | (c.G << 8) | (c.B << 16); }

        public static Run Run(string text, string brush, FontWeight weight)
        {
            return new Run(text) { Foreground = B(brush), FontWeight = weight };
        }
    }
}
