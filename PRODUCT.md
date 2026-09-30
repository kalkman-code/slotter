# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Existing product is C# / .NET Framework WinForms, compiled single-file by `build.ps1` to a dependency-free `Snappy.exe`. A native macOS port lives in `mac/` (Swift/AppKit, menu bar). This design round's deliverable is standalone self-contained HTML mockups of the Windows settings surface — a comparison artefact, not a shipped implementation.

## Users

Toby Kalkman, a solo developer on a multi-monitor Windows 11 desktop, plus anyone running the same tray-utility family. The job: get from a cold desktop to a fully arranged working desk in one action, and re-snap a stray window without dragging it into place by hand. Used daily, at the start of a work block, on a large bright screen.

## Product Purpose

Snappy opens a saved workspace — a named set of applications — and places each into its assigned rectangular zone on a specific monitor. Success is one click or one shortcut producing the exact desk the user designed, with a count of how many apps reached their zones.

## Positioning

Zone-first rather than window-first. Competing snap tools (FancyZones, Magnet) arrange windows you already opened; Snappy owns the launch as well, so a zone is a slot that names its own application and a workspace is a reproducible desk. Zones left unassigned stay live as manual drop targets, so the same map serves both launching and snapping.

## Operating Context

- Tray-resident; no main window. The tray icon is the primary control surface.
- Global shortcut `Ctrl + Alt + Space` launches the last workspace; it can be disabled, and its availability is surfaced as a status.
- Dragging a window by its title bar reveals the active workspace's zones as a full-screen overlay; releasing inside a zone snaps the window there.
- Settings is a modal Workspace Designer: workspace list, a scale zone canvas of the selected monitor, a zone inspector, and a save bar. Programs are defined once in a separate Programs list and referenced by every zone.
- Per-monitor DPI aware (PerMonitorV2); DWM frame compensation so visible edges meet saved zone boundaries; placement applied twice for terminals and Electron apps that resize after opening.
- State is `profiles.ini` beside the executable.

## Capabilities and Constraints

- Workspaces: add, rename, remove. Zones: split vertical/horizontal, delete, reset monitor, layout presets, numeric position and size as percentages (Left, Top, Width, Height).
- Programs: name, executable or shortcut, optional arguments. Renaming a program updates every zone using it.
- Tray actions: launch last workspace, pick a workspace, Settings, manage open windows, close every open app, force close every open app (with a data-loss warning), exit.
- Multi-monitor with arbitrary arrangement and mixed DPI.
- Constraint: WinForms rendering — owner-drawn controls and GDI+ only, no compositor effects, no arbitrary blur. Any direction must survive translation into that ceiling.
- Constraint: the design must scale to the rest of the family (Desky, Wally, Backy, Starty, Tabby, Gitty), which include a dense repo table, a backup dashboard and a browser popup.

## Brand Commitments

- Name "Snappy"; family names all end in `-y`.
- British English in all user-visible text.
- No commitment to the incumbent palette. The current warm-paper/terracotta scheme (`#f6f2e9` ground, `#c54f16` accent; dark sibling `#171614` / `#d97757`) is the Anthropic/Claude palette and is being deliberately replaced.
- Toby's standing rules: no horizontally scrolling regions, no orphaned rows in wrapped grids, no code comments in shipped source.

## Evidence on Hand

- Real labels and copy quoted from that source; real screen anatomy and control inventory.
- Sibling implementations for the family scale test: `Gitty\gitty\theme.py`, `backy\UiKit.cs`.
- No customers, no pricing, no testimonials, no benchmarks. None may be invented.

## Product Principles

1. The map is the product. The zone canvas is not an illustration of settings, it is the thing being designed and must dominate the screen.
2. One action from cold desktop to arranged desk; everything else is preparation for that action.
3. A zone is a named slot, not a rectangle — its identity is the app it holds, and empty is a legitimate, useful state.
4. Tray-first: the app is judged on a menu, a toast and an overlay as much as on its settings window.
5. Whatever is chosen must be a family system, not one app's skin.

## Accessibility & Inclusion

Existing code carries `AccessibleName` on every control, honours the system high-contrast palette via a `Theme(branded, systemColor)` fallback, and provides `&`-mnemonics on every button. Any direction must keep 4.5:1 on body text and never encode state in colour alone.
