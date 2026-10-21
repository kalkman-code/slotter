import AppKit
import CoreGraphics
import Darwin
import Foundation

public struct ManagedSpace: Sendable, Hashable, Identifiable {
    public var uuid: String
    public var id: UInt64
    public var type: Int
    public var ordinal: Int?
    public var label: String

    public var isFullscreen: Bool { type == 4 }

    public init(uuid: String, id: UInt64, type: Int, ordinal: Int?, label: String) {
        self.uuid = uuid
        self.id = id
        self.type = type
        self.ordinal = ordinal
        self.label = label
    }
}

public struct ManagedDisplaySpaces: Sendable, Hashable, Identifiable {
    public var displayUUID: String
    public var displayName: String
    public var spaces: [ManagedSpace]
    public var currentSpaceUUID: String?

    public var id: String { displayUUID }

    public init(displayUUID: String, displayName: String, spaces: [ManagedSpace], currentSpaceUUID: String?) {
        self.displayUUID = displayUUID
        self.displayName = displayName
        self.spaces = spaces
        self.currentSpaceUUID = currentSpaceUUID
    }

    public var currentSpace: ManagedSpace? { spaces.first { $0.uuid == currentSpaceUUID } }
}

public struct SpaceSnapshot: Sendable, Hashable {
    public var available: Bool
    public var displays: [ManagedDisplaySpaces]

    public init(available: Bool, displays: [ManagedDisplaySpaces] = []) {
        self.available = available
        self.displays = displays
    }
}

public protocol SpaceRegistryProviding {
    func snapshot() -> SpaceSnapshot
}

public final class SpaceRegistry: SpaceRegistryProviding, @unchecked Sendable {
    public static let shared = SpaceRegistry()

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyManagedSpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias ActiveSpace = @convention(c) (Int32) -> UInt64

    private let library: UnsafeMutableRawPointer?
    private let mainConnection: MainConnection?
    private let copyManagedSpaces: CopyManagedSpaces?
    private let activeSpace: ActiveSpace?

    public init() {
        library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        mainConnection = Self.symbol("CGSMainConnectionID", in: library, as: MainConnection.self)
        copyManagedSpaces = Self.symbol("CGSCopyManagedDisplaySpaces", in: library, as: CopyManagedSpaces.self)
        activeSpace = Self.symbol("CGSGetActiveSpace", in: library, as: ActiveSpace.self)
    }

    public func snapshot() -> SpaceSnapshot {
        guard let mainConnection, let copyManagedSpaces, let activeSpace else { return SpaceSnapshot(available: false) }
        let connection = mainConnection()
        guard let unmanaged = copyManagedSpaces(connection) else { return SpaceSnapshot(available: false) }
        let managed = unmanaged.takeRetainedValue() as? [[String: Any]] ?? []
        guard !managed.isEmpty else { return SpaceSnapshot(available: false) }

        let displays = DisplayRegistry.current.displays
        let activeID = activeSpace(connection)
        var result: [ManagedDisplaySpaces] = []

        for item in managed {
            guard let identifier = item["Display Identifier"] as? String,
                  let rawSpaces = item["Spaces"] as? [[String: Any]] else { continue }
            let targetDisplays: [DisplayInfo]
            if identifier == "Main" {
                targetDisplays = displays
            } else if let display = displays.first(where: { $0.uuid.caseInsensitiveCompare(identifier) == .orderedSame }) {
                targetDisplays = [display]
            } else {
                continue
            }

            let currentSpace = item["Current Space"] as? [String: Any]
            guard let parsed = Self.parseSpaceData(rawSpaces: rawSpaces, currentSpace: currentSpace,
                                                   activeSpaceID: targetDisplays.first?.isPrimary == true ? activeID : 0)
            else { continue }

            for display in targetDisplays {
                result.append(ManagedDisplaySpaces(displayUUID: display.uuid,
                                                    displayName: display.name,
                                                    spaces: parsed.spaces,
                                                    currentSpaceUUID: parsed.currentSpaceUUID))
            }
        }

        return SpaceSnapshot(available: !result.isEmpty, displays: result)
    }

    private static func symbol<T>(_ name: String, in library: UnsafeMutableRawPointer?, as type: T.Type) -> T? {
        guard let library, let address = dlsym(library, name) else { return nil }
        return unsafeBitCast(address, to: type)
    }

    static func parseDisplaySpaces(_ item: [String: Any], displayUUID: String, displayName: String,
                                   activeSpaceID: UInt64) -> ManagedDisplaySpaces? {
        guard let rawSpaces = item["Spaces"] as? [[String: Any]] else { return nil }
        let currentSpace = item["Current Space"] as? [String: Any]
        guard let parsed = parseSpaceData(rawSpaces: rawSpaces, currentSpace: currentSpace,
                                          activeSpaceID: activeSpaceID) else { return nil }
        return ManagedDisplaySpaces(displayUUID: displayUUID, displayName: displayName,
                                    spaces: parsed.spaces, currentSpaceUUID: parsed.currentSpaceUUID)
    }

    private static func parseSpaceData(rawSpaces: [[String: Any]], currentSpace: [String: Any]?,
                                       activeSpaceID: UInt64) -> (spaces: [ManagedSpace], currentSpaceUUID: String?)? {
        var desktopOrdinal = 0
        let spaces = rawSpaces.compactMap { raw -> ManagedSpace? in
            guard let uuid = raw["uuid"] as? String,
                  let number = managedSpaceID(in: raw) else { return nil }
            let type = (raw["type"] as? NSNumber)?.intValue ?? 0
            if type == 0 {
                desktopOrdinal += 1
                return ManagedSpace(uuid: uuid, id: number, type: type,
                                    ordinal: desktopOrdinal, label: "Desktop \(desktopOrdinal)")
            }
            return ManagedSpace(uuid: uuid, id: number, type: type, ordinal: nil, label: "Fullscreen")
        }
        guard !spaces.isEmpty else { return nil }
        let currentID = currentSpace.flatMap { managedSpaceID(in: $0) } ?? activeSpaceID
        return (spaces, spaces.first { $0.id == currentID }?.uuid)
    }

    private static func managedSpaceID(in dictionary: [String: Any]) -> UInt64? {
        (dictionary["ManagedSpaceID"] as? NSNumber)?.uint64Value
            ?? (dictionary["id64"] as? NSNumber)?.uint64Value
    }
}

public struct VirtualPlateResolver {
    private let registry: any SpaceRegistryProviding

    public init(registry: any SpaceRegistryProviding = SpaceRegistry.shared) {
        self.registry = registry
    }

    public func resolve(manualWorkspace: Workspace?, workspaces: [Workspace])
        -> (snapshot: SpaceSnapshot, workspacesByDisplay: [String: Workspace]) {
        let snapshot = registry.snapshot()
        let activeWorkspace = manualWorkspace.flatMap { active in
            workspaces.first { $0.id == active.id }
        } ?? manualWorkspace
        var resolved: [String: Workspace] = [:]
        for display in snapshot.displays {
            guard snapshot.available, let current = display.currentSpace, !current.isFullscreen else {
                if let activeWorkspace { resolved[display.displayUUID] = physicalWorkspace(activeWorkspace) }
                continue
            }
            guard let activeWorkspace else { continue }
            let plate = activeWorkspace.virtualPlates.first(where: {
                    $0.desktopID == current.uuid && matchesDisplay($0.monitor, displayUUID: display.displayUUID)
                })
            guard let plate else {
                resolved[display.displayUUID] = physicalWorkspace(activeWorkspace)
                continue
            }
            var resolvedWorkspace = activeWorkspace
            resolvedWorkspace.zones = activeWorkspace.zones.filter {
                ($0.plateID == nil && !matchesDisplay($0.monitor, displayUUID: display.displayUUID))
                    || $0.plateID == plate.id
            }
            resolved[display.displayUUID] = resolvedWorkspace
        }

        if resolved.isEmpty, let activeWorkspace {
            for display in DisplayRegistry.current.displays {
                resolved[display.uuid] = physicalWorkspace(activeWorkspace)
            }
        }
        return (snapshot, resolved)
    }

    private func physicalWorkspace(_ workspace: Workspace) -> Workspace {
        var physical = workspace
        physical.zones = workspace.zones.filter { $0.plateID == nil }
        return physical
    }

    private func matchesDisplay(_ monitor: MonitorRef, displayUUID: String) -> Bool {
        let uuid = DisplayRegistry.resolve(monitor)?.uuid ?? monitor.uuid
        return uuid?.caseInsensitiveCompare(displayUUID) == .orderedSame
    }
}
