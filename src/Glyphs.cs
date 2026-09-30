namespace Snappy
{
    // Segoe Fluent Icons code points. Windows 11's own symbol set rather than
    // hand-drawn paths -- see Wally's Glyphs.cs for the reasoning; this is the same
    // approach, same font.
    //
    // Written as escapes, not literal characters: these are private-use code points
    // and an editor or a re-encode will turn them into question marks.
    public static class Glyphs
    {
        public const string Workspace = "\uE7F4";  // TVMonitor
        public const string Settings  = "\uE713";  // Settings
        public const string Startup   = "\uE7E8";  // PowerButton
        public const string Hotkey    = "\uE765";  // KeyboardClassic
        public const string Windows   = "\uE7F4";  // TVMonitor
        public const string Close     = "\uE71A";  // Stop
        public const string Kill      = "\uE74D";  // Delete
        public const string Exit      = "\uE8BB";  // ChromeClose
    }
}
