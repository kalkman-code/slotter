using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows.Input;

namespace Slotter
{
    public enum SnapAction
    {
        LaunchWorkspace, LeftHalf, RightHalf, TopHalf, BottomHalf,
        TopLeft, TopRight, BottomLeft, BottomRight,
        LeftThird, CentreThird, RightThird, LeftTwoThirds, RightTwoThirds,
        Maximise, Centre, Restore, NextDisplay, PreviousDisplay
    }

    public sealed class KeyCombo : IEquatable<KeyCombo>
    {
        public Key Key { get; private set; }
        public ModifierKeys Modifiers { get; private set; }

        public KeyCombo(Key key, ModifierKeys modifiers) { Key = key; Modifiers = modifiers; }
        public bool Equals(KeyCombo other) { return other != null && Key == other.Key && Modifiers == other.Modifiers; }
        public override bool Equals(object obj) { return Equals(obj as KeyCombo); }
        public override int GetHashCode() { return ((int)Key * 397) ^ (int)Modifiers; }

        public string Format()
        {
            List<string> parts = new List<string>();
            if ((Modifiers & ModifierKeys.Control) != 0) parts.Add("Ctrl");
            if ((Modifiers & ModifierKeys.Alt) != 0) parts.Add("Alt");
            if ((Modifiers & ModifierKeys.Shift) != 0) parts.Add("Shift");
            if ((Modifiers & ModifierKeys.Windows) != 0) parts.Add("Win");
            parts.Add(KeyName(Key));
            return string.Join("+", parts);
        }

        public static bool TryParse(string value, out KeyCombo combo)
        {
            combo = null;
            if (string.IsNullOrWhiteSpace(value) || value.Trim().Equals("none", StringComparison.OrdinalIgnoreCase)) return false;
            string[] parts = value.Split('+');
            ModifierKeys modifiers = ModifierKeys.None;
            for (int i = 0; i < parts.Length - 1; i++)
            {
                string part = parts[i].Trim();
                if (part.Equals("Ctrl", StringComparison.OrdinalIgnoreCase) || part.Equals("Control", StringComparison.OrdinalIgnoreCase)) modifiers |= ModifierKeys.Control;
                else if (part.Equals("Alt", StringComparison.OrdinalIgnoreCase)) modifiers |= ModifierKeys.Alt;
                else if (part.Equals("Shift", StringComparison.OrdinalIgnoreCase)) modifiers |= ModifierKeys.Shift;
                else if (part.Equals("Win", StringComparison.OrdinalIgnoreCase) || part.Equals("Windows", StringComparison.OrdinalIgnoreCase)) modifiers |= ModifierKeys.Windows;
                else return false;
            }
            Key key;
            if (modifiers == ModifierKeys.None || !TryKey(parts[parts.Length - 1].Trim(), out key)) return false;
            combo = new KeyCombo(key, modifiers);
            return true;
        }

        public static string KeyName(Key key)
        {
            if (key == Key.Left) return "Left";
            if (key == Key.Right) return "Right";
            if (key == Key.Up) return "Up";
            if (key == Key.Down) return "Down";
            if (key == Key.Return) return "Enter";
            if (key == Key.Back) return "Backspace";
            if (key == Key.Space) return "Space";
            return key.ToString();
        }

        static bool TryKey(string name, out Key key)
        {
            if (name.Equals("Backspace", StringComparison.OrdinalIgnoreCase)) { key = Key.Back; return true; }
            if (name.Equals("Enter", StringComparison.OrdinalIgnoreCase) || name.Equals("Return", StringComparison.OrdinalIgnoreCase)) { key = Key.Return; return true; }
            if (name.Equals("Space", StringComparison.OrdinalIgnoreCase)) { key = Key.Space; return true; }
            if (!Enum.TryParse(name, true, out key) || key == Key.None || key == Key.System) return false;
            return key != Key.LeftAlt && key != Key.RightAlt && key != Key.LeftCtrl && key != Key.RightCtrl
                && key != Key.LeftShift && key != Key.RightShift && key != Key.LWin && key != Key.RWin;
        }
    }

    public static class ShortcutTable
    {
        public static readonly SnapAction[] All = (SnapAction[])Enum.GetValues(typeof(SnapAction));
        public static readonly SnapAction[] Workspace = { SnapAction.LaunchWorkspace };
        public static readonly SnapAction[] Halves = { SnapAction.LeftHalf, SnapAction.RightHalf, SnapAction.TopHalf, SnapAction.BottomHalf };
        public static readonly SnapAction[] Corners = { SnapAction.TopLeft, SnapAction.TopRight, SnapAction.BottomLeft, SnapAction.BottomRight };
        public static readonly SnapAction[] Thirds = { SnapAction.LeftThird, SnapAction.CentreThird, SnapAction.RightThird, SnapAction.LeftTwoThirds, SnapAction.RightTwoThirds };
        public static readonly SnapAction[] Other = { SnapAction.Maximise, SnapAction.Centre, SnapAction.Restore };
        public static readonly SnapAction[] Displays = { SnapAction.NextDisplay, SnapAction.PreviousDisplay };

        public static string Title(SnapAction action)
        {
            string value = action.ToString();
            if (action == SnapAction.LaunchWorkspace) return "Launch last workspace";
            if (action == SnapAction.Maximise) return "Maximise";
            if (action == SnapAction.Centre) return "Centre";
            if (action == SnapAction.NextDisplay) return "Next display";
            if (action == SnapAction.PreviousDisplay) return "Previous display";
            return string.Concat(value.Select((c, i) => i > 0 && char.IsUpper(c) ? " " + c : c.ToString()));
        }

        public static Dictionary<SnapAction, KeyCombo> Defaults()
        {
            Dictionary<SnapAction, KeyCombo> result = new Dictionary<SnapAction, KeyCombo>();
            Set(result, SnapAction.LaunchWorkspace, Key.Space, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.LeftHalf, Key.Left, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.RightHalf, Key.Right, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.TopHalf, Key.Up, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.BottomHalf, Key.Down, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.TopLeft, Key.U, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.TopRight, Key.I, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.BottomLeft, Key.J, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.BottomRight, Key.K, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.LeftThird, Key.D, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.CentreThird, Key.F, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.RightThird, Key.G, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.LeftTwoThirds, Key.E, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.RightTwoThirds, Key.T, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.Maximise, Key.Return, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.Centre, Key.C, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.Restore, Key.Back, ModifierKeys.Control | ModifierKeys.Alt);
            Set(result, SnapAction.NextDisplay, Key.Right, ModifierKeys.Control | ModifierKeys.Alt | ModifierKeys.Windows);
            Set(result, SnapAction.PreviousDisplay, Key.Left, ModifierKeys.Control | ModifierKeys.Alt | ModifierKeys.Windows);
            return result;
        }

        static void Set(Dictionary<SnapAction, KeyCombo> table, SnapAction action, Key key, ModifierKeys modifiers)
        { table[action] = new KeyCombo(key, modifiers); }

        public static Dictionary<SnapAction, KeyCombo> Read()
        {
            Dictionary<SnapAction, KeyCombo> table = Defaults();
            foreach (SnapAction action in All)
            {
                string raw = Config.IniRead("Shortcuts", action.ToString(), "");
                if (raw.Length == 0) continue;
                if (raw.Equals("none", StringComparison.OrdinalIgnoreCase)) { table.Remove(action); continue; }
                KeyCombo combo;
                if (KeyCombo.TryParse(raw, out combo)) table[action] = combo;
                else Log.Write("bad shortcut in config: " + action);
            }
            return table;
        }

        public static string ToIni(Dictionary<SnapAction, KeyCombo> table, SnapAction action)
        { KeyCombo combo; return table.TryGetValue(action, out combo) ? combo.Format() : "none"; }
    }
}
