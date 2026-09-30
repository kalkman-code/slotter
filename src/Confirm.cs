using System.Windows;
using System.Windows.Controls;
using Ykit;

namespace Snappy
{
    // The one modal shape Snappy needs for a yes/no question, wearing the same chrome
    // as every other window rather than the system message box.
    public sealed class Confirm : DeskWindow
    {
        bool answer;

        Confirm(string title, string detail, string confirmLabel, bool danger)
        {
            Title = "Snappy";
            Icon = App.WindowIcon;
            SizeToContent = SizeToContent.Height;
            Width = 440;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false;
            WindowStartupLocation = WindowStartupLocation.CenterOwner;

            StackPanel body = new StackPanel { Margin = new Thickness(22, 20, 22, 8) };

            TextBlock head = new TextBlock { Text = title };
            head.SetResourceReference(FrameworkElement.StyleProperty, "Desk.Text.InspectorHeading");
            body.Children.Add(head);

            TextBlock words = new TextBlock { Text = detail, Margin = new Thickness(0, 6, 0, 0) };
            words.SetResourceReference(FrameworkElement.StyleProperty, "Desk.Text.Secondary");
            body.Children.Add(words);

            Border bar = new Border();
            bar.SetResourceReference(FrameworkElement.StyleProperty, "Desk.CommitBar");
            StackPanel actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };

            Button keep = new Button { Content = "Keep editing", Margin = new Thickness(0, 0, 9, 0), IsCancel = true };
            keep.SetResourceReference(FrameworkElement.StyleProperty, "Desk.Button");
            keep.Click += delegate { answer = false; Close(); };

            Button go = new Button { Content = confirmLabel, IsDefault = true };
            go.SetResourceReference(FrameworkElement.StyleProperty, "Desk.Button.Primary");
            if (danger)
            {
                go.SetResourceReference(Button.BackgroundProperty, "DangerBrush");
                go.SetResourceReference(Button.BorderBrushProperty, "DangerBrush");
            }
            go.Click += delegate { answer = true; Close(); };

            actions.Children.Add(keep);
            actions.Children.Add(go);
            bar.Child = actions;

            DockPanel root = new DockPanel();
            DockPanel.SetDock(bar, Dock.Bottom);
            root.Children.Add(bar);
            root.Children.Add(body);
            Content = root;
        }

        public static bool Ask(Window owner, string title, string detail, string confirmLabel, bool danger)
        {
            Confirm dialog = new Confirm(title, detail, confirmLabel, danger);
            dialog.Owner = owner;
            dialog.ShowDialog();
            return dialog.answer;
        }
    }
}
