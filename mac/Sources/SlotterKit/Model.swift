import Foundation

public struct MonitorRef: Sendable, Hashable {
    public var ordinal: Int
    public var uuid: String?
    public var legacyKey: String?
    public var duplicateIndex: Int

    public init(ordinal: Int, uuid: String? = nil, legacyKey: String? = nil, duplicateIndex: Int = 0) {
        self.ordinal = ordinal
        self.uuid = uuid
        self.legacyKey = legacyKey
        self.duplicateIndex = duplicateIndex
    }
}

public struct Zone: Sendable, Hashable, Identifiable {
    public var id = UUID()
    public var monitor: MonitorRef
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    public var program: String?
    public var plateID: UUID?

    public init(monitor: MonitorRef, x: Double, y: Double, w: Double, h: Double, program: String? = nil,
                plateID: UUID? = nil) {
        self.monitor = monitor
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.program = program
        self.plateID = plateID
    }

    public func clamped() -> Zone {
        var copy = self
        copy.x = min(max(Self.round2(x), 0), 99)
        copy.y = min(max(Self.round2(y), 0), 99)
        copy.w = min(max(Self.round2(w), 1), 100 - copy.x)
        copy.h = min(max(Self.round2(h), 1), 100 - copy.y)
        return copy
    }

    public var isSplittableHorizontally: Bool { w >= 2 }
    public var isSplittableVertically: Bool { h >= 2 }

    private static func round2(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (value * 100).rounded() / 100
    }
}

public struct Workspace: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var zones: [Zone]
    public var virtualPlates: [VirtualPlate]

    public init(name: String, zones: [Zone] = [], virtualPlates: [VirtualPlate] = [], id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.zones = zones
        self.virtualPlates = virtualPlates
    }
}

public struct VirtualPlate: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var monitor: MonitorRef
    public var desktopID: String?
    public var followsDesktopName: Bool
    public var closedDesktopLabel: String?

    public init(id: UUID = UUID(), name: String, monitor: MonitorRef, desktopID: String?,
                followsDesktopName: Bool? = nil, closedDesktopLabel: String? = nil) {
        self.id = id
        self.name = name
        self.monitor = monitor
        self.desktopID = desktopID
        self.followsDesktopName = followsDesktopName ?? (name.range(of: #"^Desktop [1-9][0-9]*$"#, options: .regularExpression) != nil)
        self.closedDesktopLabel = closedDesktopLabel
    }
}

extension Workspace {
    @discardableResult
    public mutating func reconcileDesktops(_ snapshot: SpaceSnapshot) -> Bool {
        guard snapshot.available else { return false }
        let before = virtualPlates
        for index in virtualPlates.indices {
            let plate = virtualPlates[index]
            guard let id = plate.desktopID,
                  let display = snapshot.displays.first(where: {
                      if let uuid = plate.monitor.uuid { return uuid.caseInsensitiveCompare($0.displayUUID) == .orderedSame }
                      return DisplayRegistry.resolve(plate.monitor)?.uuid.caseInsensitiveCompare($0.displayUUID) == .orderedSame
                  }), !display.spaces.isEmpty else { continue }
            if let desktop = display.spaces.first(where: { $0.uuid == id && $0.type == 0 }) {
                if plate.followsDesktopName { virtualPlates[index].name = desktop.label }
            } else {
                virtualPlates[index].desktopID = nil
                virtualPlates[index].closedDesktopLabel = plate.name
            }
        }
        return before != virtualPlates
    }
}

public struct Program: Sendable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    public var path: String
    public var arguments: String
    public var newInstance: Bool

    public init(name: String, path: String, arguments: String = "", newInstance: Bool = false) {
        self.name = name
        self.path = path
        self.arguments = arguments
        self.newInstance = newInstance
    }

    public var isAppBundle: Bool { path.hasSuffix(".app") || path.hasSuffix(".app/") }
}

public struct SlotterConfig: Sendable {
    public var workspaces: [Workspace]
    public var programs: [Program]
    public var lastWorkspace: String
    public var startAtLogin: Bool
    public var shortcuts: [String: String]
    public var desktopSetups: [DesktopSetup]

    public init(workspaces: [Workspace] = [],
                programs: [Program] = [],
                lastWorkspace: String = "",
                startAtLogin: Bool = false,
                shortcuts: [String: String] = [:], desktopSetups: [DesktopSetup] = []) {
        self.workspaces = workspaces
        self.programs = programs
        self.lastWorkspace = lastWorkspace
        self.startAtLogin = startAtLogin
        self.shortcuts = shortcuts
        self.desktopSetups = desktopSetups
    }

    public func workspace(named name: String) -> Workspace? {
        workspaces.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func program(named name: String) -> Program? {
        programs.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

public struct DesktopSetup: Sendable, Hashable, Identifiable {
    public var name: String
    public var zones: [Zone]
    public var id: String { name }
    public init(name: String, zones: [Zone]) { self.name = name; self.zones = zones }
}

public enum Validate {
    public static let reservedSections: Set<String> = ["profiles", "programs", "panel", "settings", "shortcuts", "spacebindings", "virtualplates", "desktopsetups"]

    public static func workspaceName(_ raw: String, excluding existing: Workspace? = nil, in workspaces: [Workspace]) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Give the workspace a name." }
        if name.count > 48 { return "Keep the name to 48 characters or fewer." }
        if name.contains(where: { $0 == "," || $0 == "[" || $0 == "]" }) {
            return "Names cannot contain [ ] or ,"
        }
        if reservedSections.contains(name.lowercased()) { return "\"\(name)\" is a reserved name." }
        if workspaces.contains(where: { $0.id != existing?.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return "A workspace with that name already exists."
        }
        return nil
    }

    public static func programName(_ raw: String, excluding existing: Program? = nil, in programs: [Program]) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Give the program a name." }
        if name.count > 64 { return "Keep the name to 64 characters or fewer." }
        if programs.contains(where: { $0.id != existing?.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return "A program with that name already exists."
        }
        return nil
    }

    public static func programPath(_ raw: String) -> String? {
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty { return "Choose an application or executable." }
        if !FileManager.default.fileExists(atPath: path) { return "Nothing exists at that path." }
        return nil
    }
}
