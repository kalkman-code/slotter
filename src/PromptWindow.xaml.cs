using System;
using System.Windows;

namespace Snappy
{
    // A single text-entry question, wearing Desk chrome, used for naming and
    // renaming a workspace.
    public partial class PromptWindow : Ykit.DeskWindow
    {
        readonly Func<string, string> validate;
        bool accepted;

        public PromptWindow(string prompt, string initial, Func<string, string> validate)
        {
            InitializeComponent();
            Icon = App.WindowIcon;
            this.validate = validate;
            Prompt.Text = prompt;
            NameBox.Text = initial ?? "";
            SaveButton.Click += OnSave;
            Loaded += delegate { NameBox.Focus(); NameBox.SelectAll(); };
        }

        void OnSave(object sender, RoutedEventArgs e)
        {
            string name = NameBox.Text.Trim();
            string message = validate(name);
            if (message != null)
            {
                Error.Text = message;
                Error.Visibility = Visibility.Visible;
                NameBox.Focus();
                return;
            }
            accepted = true;
            Close();
        }

        public static string Ask(Window owner, string prompt, string initial, Func<string, string> validate)
        {
            PromptWindow dialog = new PromptWindow(prompt, initial, validate);
            dialog.Owner = owner;
            dialog.ShowDialog();
            return dialog.accepted ? dialog.NameBox.Text.Trim() : null;
        }
    }
}
