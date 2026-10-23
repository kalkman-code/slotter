# Slotter 1.0.0-alpha.2

This is an alpha release. Virtual desktop detection uses undocumented operating system data and
may stop working after an OS update. The Windows executable is signed by Toby Kalkman using Certum
open source code signing. SmartScreen may still warn on a new download until the certificate builds
reputation. macOS requires Accessibility permission to move other apps' windows.

## Updates itself

Alpha.1 has no updater, so download alpha.2 once by hand. From alpha.2 on, Slotter updates itself.

It checks once a day, and on Windows at launch too. It asks before installing: install now, later,
or skip that version. On macOS you can choose to install updates automatically instead. Turn checking off under Updates in Settings on macOS, or Automatic
update checks on Windows. A check fetches only the update list and its release notes; no system information is sent.
Updates are verified before they install, and if an updated Windows Slotter fails to start, the previous version is put back.

## New for virtual desktops

- Desktop labels: each plate shows its desktop number, such as macOS Desktop 2, beside any name
  you give it.
- Show desktop: switches to that plate's desktop. On macOS it uses your Switch to Desktop shortcut
  and tells you if it is off.
- Saved setups: save a plate's layout by name from its Modes or Setups… button, then load it
  onto another desktop. Undo puts the old layout back.

## Fixes

- Closing a desktop moves its layout to the Bench, labelled Closed and its old name, instead of leaving a broken
  duplicate.
- New and removed desktops show in the picker straight away; a missing one says Desktop
  unavailable, not Desktop 0.
- Adding a desktop works with one monitor, and empty plates have a clear Set up zones button.
- On Windows, the desk's add, set up, Bench and rename buttons work, with Undo.
- Launching a workspace opens the current desktop's apps, and stops if you switch desktop midway.
- Apps with a large minimum size stay on screen when snapped.
- Labels stay readable with many desktops or a small window.
- Fixed a crash dragging Slotter's own window on macOS, and a first-run crash on Windows.
- A damaged settings file no longer hangs Slotter at startup.

## Install

- **Windows**: download and unzip `Slotter-1.0.0-alpha.2-win-x64.zip`, then run `Slotter.exe`. It
  asks for administrator permission when it starts so it can move elevated windows.
- **macOS**: open `Slotter-1.0.0-alpha.2.dmg`, drag Slotter to Applications, then open it and allow
  Accessibility permission when macOS asks.

## Checksums

SHA-256 (macOS DMG): `18e6f5bffc8f6cba50f6174c2b7edb82f6e20b03d177ed6a89116b1b56cfeced`

SHA-256 (Windows ZIP): `7403919f1950a0bda492ed26215eeea5a3794078e594e7d0fdf455b6742577a4`
