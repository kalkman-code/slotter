import CoreGraphics
import Foundation

/// What a monitor looked like the last time it was connected, so the designer can still draw it
/// by name and size once it is unplugged. App state in UserDefaults, not part of profiles.ini.
public struct RememberedMonitor: Codable, Sendable, Hashable {
    public var name: String
    public var pixelSize: CGSize
    public var pointSize: CGSize
    public var physicalSize: CGSize
    public var top: CGFloat

    public init(name: String, pixelSize: CGSize, pointSize: CGSize, physicalSize: CGSize, top: CGFloat) {
        self.name = name
        self.pixelSize = pixelSize
        self.pointSize = pointSize
        self.physicalSize = physicalSize
        self.top = top
    }
}

public enum MonitorMemory {
    private static let key = "knownMonitors"

    public static func load() -> [String: RememberedMonitor] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let known = try? JSONDecoder().decode([String: RememberedMonitor].self, from: data) else { return [:] }
        return known
    }

    public static func record(_ displays: [DisplayInfo]) {
        var known = load()
        for display in displays {
            known[display.uuid] = RememberedMonitor(name: display.name, pixelSize: display.pixelSize,
                                                    pointSize: display.pointSize, physicalSize: display.physicalSize,
                                                    top: display.frameAX.minY)
        }
        guard let data = try? JSONEncoder().encode(known) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
