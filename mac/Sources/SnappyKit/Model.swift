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

    public init(monitor: MonitorRef, x: Double, y: Double, w: Double, h: Double, program: String? = nil) {
        self.monitor = monitor
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.program = program
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
    public var id = UUID()
    public var name: String
    public var zones: [Zone]

    public init(name: String, zones: [Zone] = []) {
        self.name = name
        self.zones = zones
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

public struct SnappyConfig: Sendable {
    public var workspaces: [Workspace]
    public var programs: [Program]
    public var lastWorkspace: String
    public var startAtLogin: Bool
    public var shortcuts: [String: String]

    public init(workspaces: [Workspace] = [],
                programs: [Program] = [],
                lastWorkspace: String = "",
                startAtLogin: Bool = false,
                shortcuts: [String: String] = [:]) {
        self.workspaces = workspaces
        self.programs = programs
        self.lastWorkspace = lastWorkspace
        self.startAtLogin = startAtLogin
        self.shortcuts = shortcuts
    }

    public func workspace(named name: String) -> Workspace? {
        workspaces.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public func program(named name: String) -> Program? {
        programs.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

public enum Validate {
    public static let reservedSections: Set<String> = ["profiles", "programs", "panel", "settings", "shortcuts"]

    public static func workspaceName(_ raw: String, excluding existing: Workspace? = nil, in workspaces: [Workspace]) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Enter a workspace name." }
        if name.count > 48 { return "Keep the name to 48 characters or fewer." }
        if name.contains(where: { $0 == "," || $0 == "[" || $0 == "]" }) {
            return "A name cannot contain a comma or square brackets."
        }
        if reservedSections.contains(name.lowercased()) { return "\"\(name)\" is a reserved name." }
        if workspaces.contains(where: { $0.id != existing?.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return "A workspace called \"\(name)\" already exists."
        }
        return nil
    }

    public static func programName(_ raw: String, excluding existing: Program? = nil, in programs: [Program]) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Enter a program name." }
        if name.count > 64 { return "Keep the name to 64 characters or fewer." }
        if programs.contains(where: { $0.id != existing?.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return "A program called \"\(name)\" already exists."
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
