import AppKit
import DeskTheme
import SwiftUI

/// Snappy's own semantic names over the shared Desk palette (`ykit/swift/DeskTheme.swift`).
/// Every colour below forwards to — or is a light derivation of — a `Desk` token; nothing here
/// defines its own RGB values any more. Kept as a thin compatibility layer so the many existing
/// call sites across SnappyUI (`Theme.text`, `Theme.Size.body`, `Theme.font(...)`) did not all
/// need renaming in the same pass that swapped the palette itself. The Desk-native components
/// (`DeskEyebrow`, `DeskPanel`, `DeskInspector`, `DeskSegmented`, `DeskRow`, `DeskCommitBar`) are
/// used directly, by their own names, wherever a view adopts one.
public enum Theme {
    public static let bg = Desk.window
    public static let surface = Desk.panel
    public static let field = Desk.field
    public static let text = Desk.ink
    public static let dim = Desk.inkSecondary
    public static let accent = Desk.accent
    /// A low-opacity accent tint for "this is the selected one" fills — list rows, the selected
    /// zone. The accent's only job is marking what is selected, so this is deliberately the one
    /// place that job is drawn, rather than each screen inventing its own selection tint.
    public static let soft = Desk.accent.withAlphaComponent(0.16)
    public static let canvas = Desk.window
    public static let rule = Desk.rule
    public static let hover = Desk.fieldRaised
    public static let danger = Desk.danger
    public static let live = Desk.live
    public static let grid = Desk.rule

    public static let monitorFill = Desk.field
    public static let zoneFill = Desk.fieldRaised
    public static let zoneFillSelected = soft

    public static let accentFill = Desk.accent
    public static let onAccent = Desk.accentInk
    public static let dangerFill = Desk.danger

    /// Snappy's own caption/body/heading scale. Distinct from `Desk.Size` (the design system's
    /// type ramp, used directly by the new Desk-native components) because most of Snappy's
    /// existing text sizing predates this port and a wholesale resize is out of scope for a
    /// presentation-layer pass — this enum stays for compatibility with those call sites.
    public enum Size {
        public static let micro: CGFloat = 11
        public static let small: CGFloat = 12
        public static let body: CGFloat = 13
        public static let mid: CGFloat = 15
        public static let large: CGFloat = 16
        public static let title: CGFloat = 19
    }

    public static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        Desk.font(size, weight)
    }
}

public extension Color {
    init(theme: NSColor) { self.init(nsColor: theme) }
}
