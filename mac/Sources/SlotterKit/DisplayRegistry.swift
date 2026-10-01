import AppKit
import os

public struct DisplayInfo: Sendable, Identifiable, Hashable {
    public let id: CGDirectDisplayID
    public let uuid: String
    public let name: String
    public let frameAX: CGRect
    public let workAreaAX: CGRect
    public let pointSize: CGSize
    public let pixelSize: CGSize
    public let isPrimary: Bool
    public let duplicateIndex: Int
    /// Millimetres, from `CGDisplayScreenSize`. `.zero` when the display reports nothing usable.
    public let physicalSize: CGSize

    public init(id: CGDirectDisplayID, uuid: String, name: String, frameAX: CGRect, workAreaAX: CGRect,
                pointSize: CGSize, pixelSize: CGSize, isPrimary: Bool, duplicateIndex: Int,
                physicalSize: CGSize = .zero) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.frameAX = frameAX
        self.workAreaAX = workAreaAX
        self.pointSize = pointSize
        self.pixelSize = pixelSize
        self.isPrimary = isPrimary
        self.duplicateIndex = duplicateIndex
        self.physicalSize = physicalSize
    }

    public var legacyKeyPoints: String { "\(Int(pointSize.width))x\(Int(pointSize.height))" }
    public var legacyKeyPixels: String { "\(Int(pixelSize.width))x\(Int(pixelSize.height))" }
}

public struct DisplaySnapshot: Sendable {
    public let displays: [DisplayInfo]
    public let flipY: CGFloat

    public static let empty = DisplaySnapshot(displays: [], flipY: 0)

    public init(displays: [DisplayInfo], flipY: CGFloat) {
        self.displays = displays
        self.flipY = flipY
    }

    public func display(containing point: CGPoint) -> DisplayInfo? {
        displays.first { $0.frameAX.contains(point) }
    }

    public func display(bestFor rect: CGRect) -> DisplayInfo? {
        var best: DisplayInfo?
        var bestArea: CGFloat = -1
        for display in displays {
            let overlap = display.frameAX.intersection(rect)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                best = display
            }
        }
        return best ?? displays.first
    }

    public func ordered() -> [DisplayInfo] {
        displays.sorted {
            $0.frameAX.minX == $1.frameAX.minX ? $0.frameAX.minY < $1.frameAX.minY : $0.frameAX.minX < $1.frameAX.minX
        }
    }

    public func next(after display: DisplayInfo) -> DisplayInfo? {
        let list = ordered()
        guard list.count > 1, let index = list.firstIndex(of: display) else { return nil }
        return list[(index + 1) % list.count]
    }

    public func previous(before display: DisplayInfo) -> DisplayInfo? {
        let list = ordered()
        guard list.count > 1, let index = list.firstIndex(of: display) else { return nil }
        return list[(index - 1 + list.count) % list.count]
    }
}

public enum DisplayRegistry {
    private static let box = OSAllocatedUnfairLock(initialState: DisplaySnapshot.empty)

    public static var current: DisplaySnapshot { box.withLock { $0 } }

    @MainActor
    @discardableResult
    public static func refresh() -> DisplaySnapshot {
        let flipY = Geo.mainFlipY
        var seen: [String: Int] = [:]
        var displays: [DisplayInfo] = []

        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let id = CGDirectDisplayID(number.uint32Value)
            let uuid = uuidString(for: id)
            let index = seen[uuid, default: 0]
            seen[uuid] = index + 1

            displays.append(DisplayInfo(
                id: id,
                uuid: uuid,
                name: screen.localizedName,
                frameAX: Geo.ax(fromCocoa: screen.frame, flipY: flipY),
                workAreaAX: Geo.ax(fromCocoa: screen.visibleFrame, flipY: flipY),
                pointSize: screen.frame.size,
                pixelSize: CGSize(width: CGDisplayPixelsWide(id), height: CGDisplayPixelsHigh(id)),
                isPrimary: screen.frame.origin == .zero,
                duplicateIndex: index,
                physicalSize: physicalSize(of: id, name: screen.localizedName,
                                           pixels: CGSize(width: CGDisplayPixelsWide(id), height: CGDisplayPixelsHigh(id)))))
        }

        displays.sort {
            $0.frameAX.minX == $1.frameAX.minX ? $0.frameAX.minY < $1.frameAX.minY : $0.frameAX.minX < $1.frameAX.minX
        }

        let snapshot = DisplaySnapshot(displays: displays, flipY: flipY)
        box.withLock { $0 = snapshot }
        MonitorMemory.record(displays)
        return snapshot
    }

    public static func resolve(_ reference: MonitorRef, in snapshot: DisplaySnapshot = DisplayRegistry.current) -> DisplayInfo? {
        if let uuid = reference.uuid, !uuid.isEmpty {
            let matches = snapshot.displays.filter { $0.uuid == uuid }
            if matches.count == 1 { return matches[0] }
            if let exact = matches.first(where: { $0.duplicateIndex == reference.duplicateIndex }) { return exact }
            if let first = matches.first { return first }
        }

        if let key = reference.legacyKey, !key.isEmpty {
            if let match = snapshot.displays.first(where: { $0.legacyKeyPoints == key || $0.legacyKeyPixels == key }) {
                return match
            }
        }

        let ordinal = reference.ordinal - 1
        if ordinal >= 0 && ordinal < snapshot.displays.count { return snapshot.displays[ordinal] }
        return nil
    }

    public static func reference(for display: DisplayInfo, in snapshot: DisplaySnapshot = DisplayRegistry.current) -> MonitorRef {
        let ordinal = (snapshot.displays.firstIndex(of: display) ?? 0) + 1
        return MonitorRef(ordinal: ordinal,
                          uuid: display.uuid,
                          legacyKey: display.legacyKeyPoints,
                          duplicateIndex: display.duplicateIndex)
    }

    /// TVs and some adapters report nonsense (0, or a centimetre figure where millimetres belong);
    /// anything outside a plausible desk monitor is treated as unknown.
    /// LG TVs report 1600 × 900 mm whatever their real size, so that figure is unknown too. A
    /// diagonal in inches under `[DisplaySizes]` in profiles.ini, keyed by the display's name, wins.
    private static func physicalSize(of id: CGDirectDisplayID, name: String, pixels: CGSize) -> CGSize {
        if let text = try? String(contentsOf: ConfigStore.url, encoding: .utf8),
           let diagonal = Double(IniDocument(text: text).string("DisplaySizes", name)), diagonal > 0,
           pixels.width > 0, pixels.height > 0 {
            let across = (pixels.width * pixels.width + pixels.height * pixels.height).squareRoot()
            return CGSize(width: diagonal * 25.4 * pixels.width / across, height: diagonal * 25.4 * pixels.height / across)
        }
        let size = CGDisplayScreenSize(id)
        guard size.width >= 150, size.width <= 3000, size.height >= 80, size.height <= 2000 else { return .zero }
        if size.width.rounded() == 1600, size.height.rounded() == 900 { return .zero }
        return size
    }

    private static func uuidString(for id: CGDirectDisplayID) -> String {
        guard let cf = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, cf) as String? else {
            return "display-\(id)"
        }
        return string
    }
}
