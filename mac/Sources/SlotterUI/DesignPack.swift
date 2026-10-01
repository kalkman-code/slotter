import AppKit
import SwiftUI

/// Every colour, radius, spacing step and type size the UI uses, named by role. A different look
/// is a second value of this type, never an edit to the views; `MarginPack.swift` is the first.
public struct DesignPack: Sendable {
    public struct Palette: Sendable {
        public var ground: Color
        public var groundLow: Color
        public var desk: Color
        public var deskLow: Color
        public var deskEdge: Color
        public var drawer: Color
        public var drawerFace: Color
        public var drawerPull: Color
        public var field: Color
        public var fieldBorder: Color
        public var rule: Color
        public var floating: Color
        public var sheet: Color
        public var hover: Color
        public var ink: Color
        public var ink2: Color
        public var ink3: Color
        public var selection: Color
        public var onSelection: Color
        public var error: Color
        public var errorGround: Color
        public var faultGround: Color
        public var disabledFill: Color
        public var knobOff: Color
        public var scrim: Color
        public var shadow: Color

        public var bezel: Color
        public var bezelTop: Color
        public var bezelEdge: Color
        public var screen: Color
        public var screenTop: Color
        public var screenOff: Color
        public var screenUnused: Color
        public var stand: Color
        public var standHigh: Color
        public var standLow: Color
        public var standEdge: Color

        public var zone: Color
        public var zoneLine: Color
        public var zoneHover: Color
        public var zoneChip: Color
        public var zoneEmpty: Color
        public var zoneEmptyLine: Color
        public var zoneOfflineLine: Color
        public var pill: Color

        public var overlayDim: Color
        public var overlayLine: Color
        public var overlayLit: Color
    }

    public struct Radii: Sendable {
        public var chip: CGFloat
        public var field: CGFloat
        public var select: CGFloat
        public var tab: CGFloat
        public var bezel: CGFloat
        public var floating: CGFloat
        public var sheet: CGFloat
    }

    public struct Spacing: Sendable {
        public var hair: CGFloat
        public var tight: CGFloat
        public var small: CGFloat
        public var medium: CGFloat
        public var large: CGFloat
        public var column: CGFloat
        public var page: CGFloat
    }

    public struct TypeSizes: Sendable {
        public var caption: CGFloat
        public var label: CGFloat
        public var small: CGFloat
        public var body: CGFloat
        public var tab: CGFloat
        public var switcher: CGFloat
        public var select: CGFloat
        public var zoneNote: CGFloat
        public var heading: CGFloat
        public var title: CGFloat
    }

    /// PostScript names, one per weight, registered from `fonts/` at launch.
    public struct Typefaces: Sendable {
        public var regular: String
        public var medium: String
        public var semibold: String
        public var bold: String
        public var extraBold: String
        public var display: String
        public var labelTracking: CGFloat
    }

    public var name: String
    public var palette: Palette
    public var radii: Radii
    public var spacing: Spacing
    public var type: TypeSizes
    public var faces: Typefaces
    public var fontFiles: [String]
}

/// The pack in use. There is no switcher yet, so this is a constant.
let T = DesignPack.margin

enum Weight { case regular, medium, semibold, bold, extraBold, display }

extension DesignPack {
    func font(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .custom(face(weight), fixedSize: size)
    }

    func nsFont(_ size: CGFloat, _ weight: Weight = .regular) -> NSFont {
        NSFont(name: face(weight), size: size) ?? .systemFont(ofSize: size)
    }

    private func face(_ weight: Weight) -> String {
        switch weight {
        case .regular: faces.regular
        case .medium: faces.medium
        case .semibold: faces.semibold
        case .bold: faces.bold
        case .extraBold: faces.extraBold
        case .display: faces.display
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    var ns: NSColor { NSColor(self) }
}
