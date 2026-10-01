# Slotter for macOS

A native Swift/AppKit port of Slotter. It does two jobs: it launches a saved **workspace** — each
app into its own zone — and it is a complete **keyboard window manager** with Magnet's shortcut
set. It lives in the menu bar and has no Dock icon.

## Build and install

```bash
./build.sh --install
```

Compiles with SwiftPM, assembles `Slotter.app` by hand, renders the icon from `../Slotter.svg`, copies
Bricolage Grotesque from `../fonts` into `Resources/Fonts` (registered at launch), signs, then
installs to `/Applications`, relaunching only if it was already running, and removes a
left-over `Snappy.app`. Drop `--install` to build without installing.

`build.sh` **refuses to ad-hoc sign.** macOS binds the Accessibility grant to the code signature,
so an ad-hoc build would lose that permission on every rebuild and you would be re-granting it all
day. Override the identity with `SLOTTER_SIGN_IDENTITY` if the certificate ever changes.

Run the tests with `swift test`.

`open -a Slotter --args --settings` opens the designer directly, matching the Windows build's
`Slotter.exe --settings`. If Slotter is already running it raises the existing window rather than
starting a second copy.

## Accessibility

Slotter needs one permission and asks for nothing else. macOS only lets an app move another app's
windows through the Accessibility API, so without the grant the app runs but every snap is a no-op.
First launch shows an explainer before anything system-level opens.

If the grant ever gets into a confused state: `tccutil reset Accessibility uk.co.kalkman.slotter`.

## Keyboard

Magnet's defaults, unchanged:

| | | | |
|---|---|---|---|
| `⌃⌥←` left half | `⌃⌥→` right half | `⌃⌥↑` top half | `⌃⌥↓` bottom half |
| `⌃⌥U` top left | `⌃⌥I` top right | `⌃⌥J` bottom left | `⌃⌥K` bottom right |
| `⌃⌥D` left third | `⌃⌥F` centre third | `⌃⌥G` right third | |
| `⌃⌥E` left two thirds | `⌃⌥T` right two thirds | | |
| `⌃⌥↩` maximise | `⌃⌥C` centre | `⌃⌥⌫` restore | |
| `⌃⌥⌘→` next display | `⌃⌥⌘←` previous display | | |

These act on fixed fractions of the focused window's display, not on workspace zones. `⌃⌥⌫`
toggles, so pressing it twice returns to the snapped frame.

Rebind or disable any of them by hand in `[Shortcuts]` (see below) — there is no recorder UI.

## Dragging

**Zones are off until you ask for them.** Out of the box, dragging gives Magnet-style snapping
only: side edge for a half, corner for a quarter, top edge to maximise, bottom edge for thirds.
Launch a workspace from the menu bar and its zones become drag targets for that session; **Stop
using these zones** turns them off again. Nothing is restored at startup, so a fresh launch is
always edges-only.

**Edge bands win inside the band; zones win everywhere else.** A 12pt strip at the screen boundary
is a more deliberate gesture than "somewhere inside this zone", and most presets tile a monitor
completely — without this the edge layer could never be reached.

There is no reliable title-bar rectangle on macOS once apps merge their toolbars, so a drag is
recognised by motion rather than geometry. Two signals do the work:

- `kAXWindowMoved` from an `AXObserver` is the primary one, trusted outright. It is the window
  server reporting that the window actually moved, and a content drag never produces one.
- A frame comparison is the fallback for apps that do not post it, confirming when the window has
  moved at least 5pt and tracks the mouse within a distance-scaled tolerance.

⚠ **A window's AX position does not update while it is being dragged.** The window server moves it
and AX catches up afterwards, so reading `kAXPosition` mid-drag reports the window still sitting at
its start point however far you have dragged. Anything that rejects a gesture on "the window has
not moved" must therefore also wait — half a second here — or it cancels every fast drag before the
move notification can arrive, leaving snapping that only works if you drag slowly. This cost
several wrong diagnoses; the tell in the log is a line reading `mouse 36pt, window 0pt`.

If a drag is released before it can be classified, mouse-up settles it: the frame is read (retried
twice, for the same lag reason) and the drop is honoured when the window genuinely moved. A flick
too quick to preview still lands where you dropped it.

## Config

`~/Library/Application Support/Slotter/profiles.ini` — hand-editable, and edits are picked up live.
Comments, blank lines and any keys Slotter does not recognise survive a save untouched.

```ini
[Profiles]  List=Coding,Writing
[Coding]
  Zone1=1,0,0,50,100        ; monitor ordinal, then X/Y/W/H as percentages of the visible area
  MonUUID1=<CGDisplay UUID> ; how the display is identified
  MonKey1=1728x1117         ; fallback if the UUID is gone
  Prog1=Safari              ; optional; unassigned zones are still manual snap targets
[Panel]     LastProfile=Coding
[Settings]  StartAtLogin=1
[Programs]  Count=1
            Name1=Safari
            Exe1=/Applications/Safari.app
            Args1=
            New1=0          ; 1 launches a separate instance
[Shortcuts] leftHalf=⌃⌥⇧←   ; optional overrides; "off" disables an action
```

Displays are resolved by UUID first, then by size, then by ordinal. Profiles are per-machine —
nothing is shared with the Windows build.

## Layout

- `Sources/SlotterKit` — domain and platform. No windows, unit-testable.
- `Sources/SlotterUI` — every window. All colours, radii, spacing and type sizes live in one design pack
  (`DesignPack.swift`, values in `MarginPack.swift`); another look is another pack, not a view edit.
- `Sources/Slotter` — the executable and `AppController`.
- `Sources/SlotterIconGen` — build-time tool that draws the icon.

Three rules the code holds to:

1. **One coordinate space.** Everything internally is AX space (top-left origin, Y down). Cocoa
   space exists only inside `Geometry.swift` and where an `NSPanel` frame is assigned.
   `NSEvent.mouseLocation` is not used anywhere.
2. **Three execution domains.** `@MainActor` owns AppKit and all snap state; a serial `AX.queue`
   owns every Accessibility call; a dedicated thread owns the event-tap run loop and only copies
   primitives out of a `CGEvent`.
3. **A successful `AXUIElementSetAttributeValue` proves nothing.** It means the target app accepted
   the message; the app may still clamp or ignore it. Every placement reads the frame back and
   reconciles.

## Differences from the Windows build

Dropped because they have no macOS meaning: UAC self-elevation, the `schtasks` logon task, DWM
frame compensation (AppKit frames are the visible frames), and the whole per-monitor DPI layer.

Start-at-login is `SMAppService`, and it is tri-state — macOS can hold it in "requires approval",
which the menu reports rather than showing a checkmark that lies. Replacing the bundle in
`/Applications` can invalidate the registration, so launch reconciles the real status against the
config and re-registers when it has been lost.

The Windows build reopens the last workspace's zones on every start; the Mac build deliberately
does not (see Dragging).

Added: the Magnet keyboard layer, drag-to-edge snapping, and motion.

Toasts sit top-right under the menu bar rather than bottom-right.
