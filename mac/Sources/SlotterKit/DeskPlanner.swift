import CoreGraphics
import Foundation

/// A monitor as the designer draws it: a connected display, or one a workspace still names but
/// that is not plugged in.
public struct DeskMonitor: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let display: DisplayInfo?
    public let reference: MonitorRef
    public let resolutionLabel: String
    public let diagonalInches: Double?

    public var isConnected: Bool { display != nil }
}

/// One monitor standing on the desk. Every length is in inches, origin at the top left of the
/// arrangement, y down, so the view needs one scale factor and nothing else.
public struct DeskPlacement: Sendable, Hashable {
    public let monitor: DeskMonitor
    public let x: Double
    public let y: Double
    public let screenWidth: Double
    public let screenHeight: Double
    public let bezel: Double
    public let chin: Double
    public let neckWidth: Double
    public let footWidth: Double
    public let footHeight: Double

    public var outerWidth: Double { screenWidth + bezel * 2 }
    public var outerHeight: Double { screenHeight + bezel + chin }
    public var centreX: Double { x + outerWidth / 2 }
    public var bottom: Double { y + outerHeight }
}

public struct DeskArrangement: Sendable {
    public let placements: [DeskPlacement]
    public let width: Double
    public let deskLine: Double
    /// False when no display reported a physical size and the drawing fell back to proportions
    /// of each display's size in points.
    public let trueScale: Bool

    public var monitors: [DeskMonitor] { placements.map(\.monitor) }

    public func placement(for id: String) -> DeskPlacement? {
        placements.first { $0.monitor.id == id }
    }
}

public enum DeskPlanner {
    private static let fallbackPointsPerInch = 80.0
    private static let minimumNeck = 1.96

    public static func key(for display: DisplayInfo) -> String {
        "display:\(display.uuid)#\(display.duplicateIndex)"
    }

    /// Resolution goes through `DisplayRegistry.resolve`, the same lookup the launcher and the
    /// snap engine use, so the designer draws a zone where launching would put it today.
    public static func key(for reference: MonitorRef, in snapshot: DisplaySnapshot) -> String {
        if let display = DisplayRegistry.resolve(reference, in: snapshot) { return key(for: display) }
        if let uuid = reference.uuid, !uuid.isEmpty { return "offline:\(uuid)#\(reference.duplicateIndex)" }
        if let legacy = reference.legacyKey, !legacy.isEmpty { return "offline:\(legacy)" }
        return "offline:\(reference.ordinal)"
    }

    /// Connected displays in their OS left-to-right order, then any monitor a workspace names that
    /// is not connected. `references` is every zone's monitor across the workspaces being edited;
    /// `remembered` is `MonitorMemory`, keyed by display UUID.
    public static func arrange(_ snapshot: DisplaySnapshot, references: [MonitorRef],
                               remembered: [String: RememberedMonitor] = [:]) -> DeskArrangement {
        let connected = snapshot.ordered()

        var offline: [(key: String, ref: MonitorRef)] = []
        for ref in references {
            let key = key(for: ref, in: snapshot)
            guard key.hasPrefix("offline:"), !offline.contains(where: { $0.key == key }) else { continue }
            offline.append((key, ref))
        }

        let pitches = connected.compactMap { display -> Double? in
            guard display.physicalSize.width > 0 else { return nil }
            return Double(display.frameAX.width) / (Double(display.physicalSize.width) / 25.4)
        }
        let trueScale = !pitches.isEmpty
        let sharedPitch = trueScale ? pitches.reduce(0, +) / Double(pitches.count) : fallbackPointsPerInch

        struct Sized { var monitor: DeskMonitor; var width: Double; var height: Double; var top: Double }
        var sized: [Sized] = []

        let reference = connected.min {
            $0.frameAX.minY == $1.frameAX.minY ? $0.frameAX.height > $1.frameAX.height : $0.frameAX.minY < $1.frameAX.minY
        }
        let referencePitch = reference.map { pitch(of: $0, trueScale: trueScale, shared: sharedPitch) } ?? sharedPitch

        for display in connected {
            let pitch = pitch(of: display, trueScale: trueScale, shared: sharedPitch)
            let width = Double(display.frameAX.width) / pitch
            let height = Double(display.frameAX.height) / pitch
            let drop = Double(display.frameAX.minY - (reference?.frameAX.minY ?? 0)) / referencePitch
            let diagonal = trueScale && display.physicalSize.width > 0
                ? (width * width + height * height).squareRoot() : nil
            let monitor = DeskMonitor(
                id: key(for: display),
                name: display.name,
                display: display,
                reference: DisplayRegistry.reference(for: display, in: snapshot),
                resolutionLabel: "\(Int(display.pixelSize.width)) × \(Int(display.pixelSize.height))",
                diagonalInches: diagonal)
            sized.append(Sized(monitor: monitor, width: width, height: height, top: drop))
        }

        for (key, ref) in offline {
            if let memory = ref.uuid.flatMap({ remembered[$0] }) {
                let physical = trueScale && memory.physicalSize.width > 0
                let width = physical ? Double(memory.physicalSize.width) / 25.4 : Double(memory.pointSize.width) / sharedPitch
                let height = physical ? Double(memory.physicalSize.height) / 25.4 : Double(memory.pointSize.height) / sharedPitch
                let monitor = DeskMonitor(
                    id: key,
                    name: memory.name,
                    display: nil,
                    reference: ref,
                    resolutionLabel: "\(Int(memory.pixelSize.width)) × \(Int(memory.pixelSize.height))",
                    diagonalInches: physical ? (width * width + height * height).squareRoot() : nil)
                let drop = Double(memory.top - (reference?.frameAX.minY ?? 0)) / referencePitch
                sized.append(Sized(monitor: monitor, width: width, height: height, top: drop))
                continue
            }
            let points = legacyPoints(ref.legacyKey) ?? CGSize(width: 1920, height: 1080)
            let monitor = DeskMonitor(
                id: key,
                name: "Monitor \(ref.ordinal)",
                display: nil,
                reference: ref,
                resolutionLabel: legacyPoints(ref.legacyKey).map { "\(Int($0.width)) × \(Int($0.height))" } ?? "",
                diagonalInches: nil)
            sized.append(Sized(monitor: monitor,
                               width: Double(points.width) / sharedPitch,
                               height: Double(points.height) / sharedPitch,
                               top: 0))
        }

        let tallest = sized.map(\.height).max() ?? 1
        let meanWidth = sized.isEmpty ? 1 : sized.map(\.width).reduce(0, +) / Double(sized.count)
        let gap = max(2, meanWidth * 0.09)

        var placements: [DeskPlacement] = []
        var cursor = 0.0
        for item in sized {
            let bezel = min(max(item.width * 0.01, 0.3), 0.45)
            let placement = DeskPlacement(
                monitor: item.monitor,
                x: cursor,
                y: min(max(item.top, 0), tallest * 0.5),
                screenWidth: item.width,
                screenHeight: item.height,
                bezel: bezel,
                chin: bezel + 0.4,
                neckWidth: min(max(item.width * 0.1, 1.8), 5.5),
                footWidth: min(max(item.width * 0.36, 6), 18),
                footHeight: 0.75)
            placements.append(placement)
            cursor += placement.outerWidth + gap
        }

        let width = placements.last.map { $0.x + $0.outerWidth } ?? 1
        let deskLine = (placements.map(\.bottom).max() ?? 1) + minimumNeck
        return DeskArrangement(placements: placements, width: width, deskLine: deskLine, trueScale: trueScale)
    }

    private static func pitch(of display: DisplayInfo, trueScale: Bool, shared: Double) -> Double {
        guard trueScale, display.physicalSize.width > 0 else { return shared }
        return Double(display.frameAX.width) / (Double(display.physicalSize.width) / 25.4)
    }

    private static func legacyPoints(_ key: String?) -> CGSize? {
        guard let parts = key?.split(separator: "x"), parts.count == 2,
              let width = Double(parts[0]), let height = Double(parts[1]), width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
}
