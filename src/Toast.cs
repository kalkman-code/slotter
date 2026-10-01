using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Threading;

namespace Slotter
{
    // A short-lived card in the corner of the working area saying what just happened. Not a
    // dialog: it never takes focus and never needs dismissing.
    public sealed class Toast : Window
    {
        static Toast showing;

        readonly DispatcherTimer life = new DispatcherTimer();

        Toast(string title, string detail, bool good, string problem)
        {
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ShowActivated = false;
            ShowInTaskbar = false;
            Topmost = true;
            SizeToContent = SizeToContent.WidthAndHeight;
            ResizeMode = ResizeMode.NoResize;
            FontFamily = Ui.UiFont;
            Foreground = Ui.B("B.Ink");
            UseLayoutRounding = true;
            Content = Card(title, detail, problem);

            MouseLeftButtonDown += delegate { Close(); };
            life.Interval = TimeSpan.FromSeconds(good ? 4 : 7);
            life.Tick += delegate { Close(); };
        }

        // The card alone, so it can be drawn offscreen too. The problem, when there is one, is the
        // part of the sentence in the error colour; the words carry it either way.
        public static Border Card(string title, string detail, string problem)
        {
            Border tile = new Border
            {
                Width = 30, Height = 30, CornerRadius = new CornerRadius(6), Background = Ui.B("B.Ground"),
                VerticalAlignment = VerticalAlignment.Top,
                Child = new Viewbox { Width = 18, Height = 18, Child = Ui.Icon("G.Glyph", 16, true, Ui.B("B.Ink")) }
            };

            StackPanel words = new StackPanel { Margin = new Thickness(12, 0, 0, 0) };
            TextBlock head = Ui.Text(title, 14, FontWeights.Bold, "B.Ink");
            head.TextWrapping = TextWrapping.Wrap;
            words.Children.Add(head);
            if (!string.IsNullOrEmpty(detail) || !string.IsNullOrEmpty(problem))
            {
                TextBlock body = new TextBlock { FontSize = 12, Foreground = Ui.B("B.Ink2"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 1, 0, 0) };
                if (!string.IsNullOrEmpty(detail)) body.Inlines.Add(new Run(detail));
                if (!string.IsNullOrEmpty(problem))
                {
                    if (body.Inlines.Count > 0) body.Inlines.Add(new Run(" "));
                    body.Inlines.Add(Ui.Run(problem, "B.Error", FontWeights.Normal));
                }
                words.Children.Add(body);
            }

            DockPanel row = new DockPanel();
            DockPanel.SetDock(tile, Dock.Left);
            row.Children.Add(tile);
            row.Children.Add(words);

            Border card = new Border
            {
                Width = 340, Margin = new Thickness(24, 12, 18, 34), Padding = new Thickness(14, 12, 14, 12),
                Background = Ui.B("B.Menu"), BorderBrush = Ui.B("B.FieldBorder"), BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(6), Effect = (System.Windows.Media.Effects.Effect)Ui.R("Shadow"), Child = row
            };
            TextElement.SetFontFamily(card, Ui.UiFont);
            return card;
        }

        public static void Show(string title, string detail, bool good, string problem = null)
        {
            try
            {
                if (showing != null) showing.Close();
                Toast toast = new Toast(title, detail, good, problem);
                showing = toast;
                toast.Closed += delegate { if (ReferenceEquals(showing, toast)) showing = null; };
                toast.Show();
                toast.Place();
                toast.life.Start();
            }
            catch (Exception ex) { Log.Write("toast: " + ex.Message); }
        }

        void Place()
        {
            System.Drawing.Rectangle work = System.Windows.Forms.Screen.PrimaryScreen.WorkingArea;
            PresentationSource source = PresentationSource.FromVisual(this);
            double sx = 1, sy = 1;
            if (source != null && source.CompositionTarget != null)
            {
                sx = source.CompositionTarget.TransformToDevice.M11;
                sy = source.CompositionTarget.TransformToDevice.M22;
            }
            Left = (work.Right / sx) - ActualWidth;
            Top = (work.Bottom / sy) - ActualHeight;
        }

        protected override void OnClosed(EventArgs e)
        {
            life.Stop();
            base.OnClosed(e);
        }
    }
}
