using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace Snappy
{
    // A short-lived panel in the corner of the working area, saying what just
    // happened. Not a dialog: it never takes focus and never needs dismissing.
    public sealed class Toast : Window
    {
        static Toast showing;

        readonly DispatcherTimer life = new DispatcherTimer();

        Toast(string title, string detail, bool good)
        {
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ShowActivated = false;
            ShowInTaskbar = false;
            Topmost = true;
            SizeToContent = SizeToContent.WidthAndHeight;
            ResizeMode = ResizeMode.NoResize;

            Border shell = new Border();
            shell.SetResourceReference(Border.BackgroundProperty, "PanelBrush");
            shell.SetResourceReference(Border.BorderBrushProperty, "RuleBrush");
            shell.BorderThickness = new Thickness(1);
            shell.CornerRadius = new CornerRadius(10);
            shell.Padding = new Thickness(16, 13, 20, 15);
            shell.Effect = new System.Windows.Media.Effects.DropShadowEffect
            {
                BlurRadius = 18,
                ShadowDepth = 4,
                Opacity = 0.4,
                Color = Colors.Black
            };

            Grid grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            Ellipse dot = new Ellipse { Width = 7, Height = 7, Margin = new Thickness(0, 6, 11, 0), VerticalAlignment = VerticalAlignment.Top };
            dot.SetResourceReference(Shape.FillProperty, good ? "LiveBrush" : "DangerBrush");
            grid.Children.Add(dot);

            StackPanel words = new StackPanel { MaxWidth = 340 };
            Grid.SetColumn(words, 1);

            TextBlock head = new TextBlock { Text = title };
            head.SetResourceReference(FrameworkElement.StyleProperty, "Desk.Text.CardHeading");
            words.Children.Add(head);

            if (!string.IsNullOrEmpty(detail))
            {
                TextBlock body = new TextBlock { Text = detail, Margin = new Thickness(0, 3, 0, 0) };
                body.SetResourceReference(FrameworkElement.StyleProperty, "Desk.Text.Secondary");
                words.Children.Add(body);
            }

            grid.Children.Add(words);
            shell.Child = grid;
            Content = shell;

            MouseLeftButtonDown += delegate { Close(); };
            life.Interval = TimeSpan.FromSeconds(good ? 4 : 7);
            life.Tick += delegate { Close(); };
        }

        public static void Show(string title, string detail, bool good)
        {
            try
            {
                if (showing != null) showing.Close();
                Toast toast = new Toast(title, detail, good);
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
            Left = (work.Right / sx) - ActualWidth - 18;
            Top = (work.Bottom / sy) - ActualHeight - 18;
        }

        protected override void OnClosed(EventArgs e)
        {
            life.Stop();
            base.OnClosed(e);
        }
    }
}
