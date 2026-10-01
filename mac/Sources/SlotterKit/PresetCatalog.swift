import Foundation

public struct ZoneFraction: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

public struct LayoutPreset: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    public var zones: [ZoneFraction]
}

public enum PresetCatalog {
    public static let all: [LayoutPreset] = [
        LayoutPreset(name: "Full", zones: [ZoneFraction(0, 0, 100, 100)]),
        LayoutPreset(name: "2 columns", zones: [
            ZoneFraction(0, 0, 50, 100), ZoneFraction(50, 0, 50, 100),
        ]),
        LayoutPreset(name: "3 columns", zones: [
            ZoneFraction(0, 0, 33.33, 100), ZoneFraction(33.33, 0, 33.34, 100), ZoneFraction(66.67, 0, 33.33, 100),
        ]),
        LayoutPreset(name: "4 columns", zones: [
            ZoneFraction(0, 0, 25, 100), ZoneFraction(25, 0, 25, 100),
            ZoneFraction(50, 0, 25, 100), ZoneFraction(75, 0, 25, 100),
        ]),
        LayoutPreset(name: "2 rows", zones: [
            ZoneFraction(0, 0, 100, 50), ZoneFraction(0, 50, 100, 50),
        ]),
        LayoutPreset(name: "3 rows", zones: [
            ZoneFraction(0, 0, 100, 33.33), ZoneFraction(0, 33.33, 100, 33.34), ZoneFraction(0, 66.67, 100, 33.33),
        ]),
        LayoutPreset(name: "2 × 2 grid", zones: [
            ZoneFraction(0, 0, 50, 50), ZoneFraction(50, 0, 50, 50),
            ZoneFraction(0, 50, 50, 50), ZoneFraction(50, 50, 50, 50),
        ]),
        LayoutPreset(name: "Left half", zones: [ZoneFraction(0, 0, 50, 100)]),
        LayoutPreset(name: "Right half", zones: [ZoneFraction(50, 0, 50, 100)]),
        LayoutPreset(name: "Left third", zones: [ZoneFraction(0, 0, 33.33, 100)]),
        LayoutPreset(name: "Centre third", zones: [ZoneFraction(33.33, 0, 33.34, 100)]),
        LayoutPreset(name: "Right third", zones: [ZoneFraction(66.67, 0, 33.33, 100)]),
        LayoutPreset(name: "Left ⅔ + right ⅓", zones: [
            ZoneFraction(0, 0, 66.67, 100), ZoneFraction(66.67, 0, 33.33, 100),
        ]),
        LayoutPreset(name: "Left ⅓ + right ⅔", zones: [
            ZoneFraction(0, 0, 33.33, 100), ZoneFraction(33.33, 0, 66.67, 100),
        ]),
    ]
}

public enum ZoneOps {
    public static func splitVertical(_ zone: Zone) -> [Zone] {
        let half = (zone.w / 2 * 100).rounded() / 100
        var left = zone
        left.w = half
        var right = zone
        right.id = UUID()
        right.x = zone.x + half
        right.w = zone.w - half
        right.program = nil
        return [left.clamped(), right.clamped()]
    }

    public static func splitHorizontal(_ zone: Zone) -> [Zone] {
        let half = (zone.h / 2 * 100).rounded() / 100
        var top = zone
        top.h = half
        var bottom = zone
        bottom.id = UUID()
        bottom.y = zone.y + half
        bottom.h = zone.h - half
        bottom.program = nil
        return [top.clamped(), bottom.clamped()]
    }

    public static func zones(from preset: LayoutPreset, monitor: MonitorRef) -> [Zone] {
        preset.zones.map { Zone(monitor: monitor, x: $0.x, y: $0.y, w: $0.w, h: $0.h).clamped() }
    }
}
