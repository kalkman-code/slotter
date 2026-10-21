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
    public static func grid(columns: Int, rows: Int) -> LayoutPreset? {
        guard (1...20).contains(columns), (1...20).contains(rows) else { return nil }
        func edge(_ index: Int, _ count: Int) -> Double {
            (Double(index) * 10000 / Double(count)).rounded() / 100
        }
        let zones = (0..<rows).flatMap { row in
            (0..<columns).map { column in
                ZoneFraction(edge(column, columns), edge(row, rows),
                             edge(column + 1, columns) - edge(column, columns),
                             edge(row + 1, rows) - edge(row, rows))
            }
        }
        return LayoutPreset(name: "\(columns) × \(rows) grid", zones: zones)
    }

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
    /// Enumerate horizontal spans, then subtract the union of occupied vertical intervals.
    /// Inward rounding keeps free rectangles clear of slots with fractional edges.
    public static func largestFreeSpace(among zones: [Zone]) -> ZoneFraction? {
        let occupied = zones.compactMap { zone -> ZoneFraction? in
            guard [zone.x, zone.y, zone.w, zone.h].allSatisfy(\.isFinite), zone.w > 0, zone.h > 0 else { return nil }
            let left = max(0, zone.x), top = max(0, zone.y)
            let right = min(100, zone.x + zone.w), bottom = min(100, zone.y + zone.h)
            guard right > left, bottom > top else { return nil }
            return ZoneFraction(left, top, right - left, bottom - top)
        }
        let edges = Set([0.0, 100.0] + occupied.flatMap { [$0.x, $0.x + $0.w] }).sorted()
        var best: ZoneFraction?
        var bestArea = 0.0
        func consider(_ left: Double, _ right: Double, _ top: Double, _ bottom: Double) {
            let x = ceil(left * 100 - 0.000001) / 100
            let y = ceil(top * 100 - 0.000001) / 100
            let w = floor(right * 100 + 0.000001) / 100 - x
            let h = floor(bottom * 100 + 0.000001) / 100 - y
            guard w >= 1, h >= 1 else { return }
            let area = w * h
            if area > bestArea + 0.000001 || (abs(area - bestArea) < 0.000001 && (y, x) < (best?.y ?? 101, best?.x ?? 101)) {
                best = ZoneFraction(x, y, w, h)
                bestArea = area
            }
        }
        for leftIndex in 0..<(edges.count - 1) {
            for rightIndex in (leftIndex + 1)..<edges.count {
                let left = edges[leftIndex], right = edges[rightIndex]
                guard right - left >= 1 else { continue }
                let intervals = occupied.filter { $0.x < right - 0.0000001 && $0.x + $0.w > left + 0.0000001 }
                    .sorted { $0.y < $1.y }
                var bottom = 0.0
                for interval in intervals {
                    consider(left, right, bottom, interval.y)
                    bottom = max(bottom, interval.y + interval.h)
                }
                consider(left, right, bottom, 100)
            }
        }
        return best
    }

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
