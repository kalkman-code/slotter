using System.Collections.Generic;
using System.Windows;
using Microsoft.Win32;

namespace Snappy
{
    public partial class ProgEditWindow : Ykit.DeskWindow
    {
        readonly ProgItem item;
        readonly List<ProgItem> library;

        public ProgEditWindow(ProgItem item, List<ProgItem> library)
        {
            InitializeComponent();
            Icon = App.WindowIcon;
            this.item = item;
            this.library = library;

            NameBox.Text = item.Name;
            ExeBox.Text = item.Exe;
            ArgsBox.Text = item.Args;

            BrowseButton.Click += delegate
            {
                OpenFileDialog ofd = new OpenFileDialog { Filter = "Programs (*.exe;*.lnk)|*.exe;*.lnk|All files (*.*)|*.*" };
                if (ofd.ShowDialog(this) == true) ExeBox.Text = ofd.FileName;
            };
            SaveButton.Click += OnSave;
            Loaded += delegate { NameBox.Focus(); };
        }

        void OnSave(object sender, RoutedEventArgs e)
        {
            string name = NameBox.Text.Trim();
            if (name.Length == 0) { Fail("Enter a program name.", NameBox); return; }
            if (name.Length > 64) { Fail("Use 64 characters or fewer.", NameBox); return; }
            foreach (ProgItem other in library)
                if (other != item && string.Equals(other.Name, name, System.StringComparison.OrdinalIgnoreCase)) { Fail("A program with that name already exists.", NameBox); return; }
            if (ExeBox.Text.Trim().Length == 0) { Fail("Choose a program or shortcut.", ExeBox); return; }

            item.Name = name;
            item.Exe = ExeBox.Text.Trim();
            item.Args = ArgsBox.Text.Trim();
            DialogResult = true;
            Close();
        }

        void Fail(string message, System.Windows.Controls.TextBox focus)
        {
            Error.Text = message;
            Error.Visibility = Visibility.Visible;
            focus.Focus();
        }
    }
}
