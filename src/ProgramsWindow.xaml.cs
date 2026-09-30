using System.Collections.Generic;
using System.Windows;

namespace Snappy
{
    // Manage the reusable [Programs] library.
    public partial class ProgramsWindow : Ykit.DeskWindow
    {
        public bool Changed { get; private set; }
        readonly List<ProgItem> lib;
        readonly List<Profile> profiles;

        public ProgramsWindow(List<ProgItem> library, List<Profile> workspaceProfiles)
        {
            InitializeComponent();
            Icon = App.WindowIcon;
            lib = library;
            profiles = workspaceProfiles;

            AddButton.Click += delegate { Edit(true); };
            EditButton.Click += delegate { Edit(false); };
            RemoveButton.Click += delegate { Remove(); };
            DoneButton.Click += delegate { Close(); };
            ProgramList.SelectionChanged += delegate { UpdateActions(); };
            ProgramList.MouseDoubleClick += delegate { Edit(false); };

            Refresh();
        }

        void Refresh()
        {
            ProgramList.ItemsSource = null;
            ProgramList.ItemsSource = lib;
            EmptyText.Visibility = lib.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            UpdateActions();
        }

        void UpdateActions()
        {
            bool selected = ProgramList.SelectedItem != null;
            EditButton.IsEnabled = RemoveButton.IsEnabled = selected;
        }

        void Edit(bool isNew)
        {
            ProgItem p = isNew ? new ProgItem { Name = "", Exe = "", Args = "" } : ProgramList.SelectedItem as ProgItem;
            if (p == null) return;
            string oldName = p.Name;
            ProgEditWindow d = new ProgEditWindow(p, lib);
            d.Owner = this;
            if (d.ShowDialog() == true)
            {
                if (isNew) lib.Add(p);
                else if (!string.Equals(oldName, p.Name, System.StringComparison.OrdinalIgnoreCase)) ReplaceReferences(oldName, p.Name);
                Changed = true;
            }
            Refresh();
        }

        void Remove()
        {
            ProgItem p = ProgramList.SelectedItem as ProgItem;
            if (p == null) return;
            int uses = 0;
            foreach (Profile profile in profiles)
                foreach (Zone zone in profile.Zones)
                    if (string.Equals(zone.Prog, p.Name, System.StringComparison.OrdinalIgnoreCase)) uses++;
            string detail = uses == 0 ? "It is not assigned to any zones." : (uses == 1 ? "1 zone will be left unassigned." : uses + " zones will be left unassigned.");
            if (!Confirm.Ask(this, "Remove " + p.Name + "?", detail, "Remove program", true)) return;
            ReplaceReferences(p.Name, null);
            lib.Remove(p);
            Changed = true;
            Refresh();
        }

        void ReplaceReferences(string oldName, string newName)
        {
            foreach (Profile profile in profiles)
                foreach (Zone zone in profile.Zones)
                    if (string.Equals(zone.Prog, oldName, System.StringComparison.OrdinalIgnoreCase)) zone.Prog = newName;
        }
    }
}
