# Snappy 2.0

Snappy opens a Windows workspace and places each app into its saved screen zone. It runs from the tray, built on .NET 10 + WPF and wearing the shared Y-family "Desk" design ([`ykit/docs/desk-design-system.md`](../ykit/docs/desk-design-system.md)).

There is a native macOS port in [`mac/`](mac/README.md) — Swift/AppKit, menu bar, same workspace model, plus a full Magnet-compatible keyboard layer, also on the Desk design. The two builds share no code and keep their own profiles.

## Use Snappy

- Click the tray icon to launch a workspace, open Settings, or manage open app windows.
- Press `Ctrl + Alt + Space` to launch the last workspace. You can turn the shortcut off from the tray or Settings.
- Drag any app by its title bar to reveal the active workspace's zones, then release inside a zone to snap it there. Assigned and unassigned zones are both available.
- Snappy confirms each launch and reports how many apps reached their zones.

`Close every open app` asks visible apps to close. `Force close every open app` shows a warning before ending their processes because unsaved work can be lost.

## Set up a workspace

Open **Settings** from the tray. Add a workspace, select a monitor, and choose a preset or split an existing zone. Assign a program when Snappy should launch it automatically, or leave the zone empty to use it as a manual snap target, then save changes.

Use **Manage programs** to define each executable or shortcut once. Renaming a program updates every zone that uses it. Chrome workspaces should include `--new-window` in the program arguments when each zone needs a separate browser window.

Snappy stores workspaces and programs in `profiles.ini` beside the executable. The Settings window validates names and zone geometry before saving.

## Build and run

Run:

```powershell
.\install.ps1
```

This builds a self-contained `Snappy.exe` with `dotnet publish` (see `build.ps1`), installs it to `%LOCALAPPDATA%\Snappy`, creates the Start Menu, desktop and taskbar entries, seeds `profiles.ini` on first install only, and never adds an autostart entry on its own — Snappy asks for that from its own tray menu.

Per-monitor DPI awareness is declared in `app.manifest` (`dpiAwareness = PerMonitorV2`); WPF lays out in device-independent units, so there is no manual scaling code anywhere in the app — the `S()`/`k` scaling apparatus the WinForms build needed is gone entirely.

Snappy uses DWM frame compensation so visible window edges meet the saved zone boundaries. It applies placement twice for terminals and Electron apps that resize after opening. It self-elevates on launch (UAC) because snapping an admin window requires Snappy to run elevated too.
