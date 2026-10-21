using System;
using System.Windows;
using System.Windows.Controls;

namespace Slotter
{
    // Shared confirmation window for destructive actions.
    public sealed class Confirm : Window
    {
        bool answer;

        Confirm(string title, string detail, string confirmLabel, bool danger)
        {
            Style = Ui.S("Win");
            Title = "Slotter";
            Icon = App.WindowIcon;
            SizeToContent = SizeToContent.Height;
            Width = 440;
            ResizeMode = ResizeMode.NoResize;
            ShowInTaskbar = false;
            SourceInitialized += delegate { Ui.TintTitleBar(this); };

            StackPanel body = new StackPanel { Margin = new Thickness(22, 20, 22, 20) };
            TextBlock head = Ui.Text(title, 18, FontWeights.ExtraBold, "B.Ink");
            head.TextWrapping = TextWrapping.Wrap;
            body.Children.Add(head);
            TextBlock words = Ui.Text(detail, 13, FontWeights.Normal, "B.Ink2");
            words.TextWrapping = TextWrapping.Wrap;
            words.Margin = new Thickness(0, 6, 0, 0);
            body.Children.Add(words);

            Button keep = Ui.Button("Btn.Quiet", "Keep editing", delegate { answer = false; Close(); });
            keep.IsCancel = true;
            Button go = Ui.Button(danger ? "Btn.Danger" : "Btn.Primary", confirmLabel, delegate { answer = true; Close(); });
            go.IsDefault = true;
            go.Margin = new Thickness(8, 0, 0, 0);
            StackPanel actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            actions.Children.Add(keep);
            actions.Children.Add(go);
            Border bar = new Border
            {
                Background = Ui.B("B.Drawer2"), BorderBrush = Ui.B("B.Rule"), BorderThickness = new Thickness(0, 1, 0, 0),
                Padding = new Thickness(16, 12, 16, 12), Child = actions
            };

            DockPanel root = new DockPanel();
            DockPanel.SetDock(bar, Dock.Bottom);
            root.Children.Add(bar);
            root.Children.Add(body);
            Content = root;
        }

        public static bool Ask(Window owner, string title, string detail, string confirmLabel, bool danger)
        {
            Confirm dialog = new Confirm(title, detail, confirmLabel, danger);
            if (owner != null) { dialog.Owner = owner; dialog.WindowStartupLocation = WindowStartupLocation.CenterOwner; }
            else dialog.WindowStartupLocation = WindowStartupLocation.CenterScreen;
            dialog.ShowDialog();
            return dialog.answer;
        }
    }
}
