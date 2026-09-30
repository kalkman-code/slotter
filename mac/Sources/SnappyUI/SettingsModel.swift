import AppKit
import Observation
import SnappyKit

@MainActor
@Observable
public final class SettingsModel {
    public var workspaces: [Workspace]
    public var programs: [Program]
    public var lastWorkspace: String
    public var startAtLogin: Bool
    public var shortcuts: [String: String]

    public var selectedWorkspaceID: UUID?
    public var selectedZoneIndex: Int?
    public var selectedDisplayID: CGDirectDisplayID?
    public var pendingConfirm: PendingConfirm?

    public private(set) var dirty = false

    private let original: SnappyConfig

    public init(config: SnappyConfig) {
        original = config
        workspaces = config.workspaces
        programs = config.programs
        lastWorkspace = config.lastWorkspace
        startAtLogin = config.startAtLogin
        shortcuts = config.shortcuts
        selectedWorkspaceID = config.workspaces.first?.id
        selectedDisplayID = DisplayRegistry.current.displays.first?.id
    }

    public var config: SnappyConfig {
        SnappyConfig(workspaces: workspaces,
                     programs: programs,
                     lastWorkspace: lastWorkspace,
                     startAtLogin: startAtLogin,
                     shortcuts: shortcuts)
    }

    public var selectedWorkspace: Workspace? {
        guard let id = selectedWorkspaceID else { return nil }
        return workspaces.first { $0.id == id }
    }

    public var selectedWorkspaceIndex: Int? {
        guard let id = selectedWorkspaceID else { return nil }
        return workspaces.firstIndex { $0.id == id }
    }

    public var selectedZone: Zone? {
        guard let workspace = selectedWorkspace, let index = selectedZoneIndex,
              index >= 0, index < workspace.zones.count else { return nil }
        return workspace.zones[index]
    }

    public var selectedDisplay: DisplayInfo? {
        let snapshot = DisplayRegistry.current
        return snapshot.displays.first { $0.id == selectedDisplayID } ?? snapshot.displays.first
    }

    public func markDirty() { dirty = true }

    public func confirm(_ request: ConfirmRequest, action: @escaping () -> Void) {
        pendingConfirm = PendingConfirm(request: request, action: action)
    }

    public func mutateSelectedWorkspace(_ transform: (inout Workspace) -> Void) {
        guard let index = selectedWorkspaceIndex else { return }
        transform(&workspaces[index])
        markDirty()
    }

    public func updateSelectedZone(_ transform: (inout Zone) -> Void) {
        guard let workspaceIndex = selectedWorkspaceIndex,
              let zoneIndex = selectedZoneIndex,
              zoneIndex < workspaces[workspaceIndex].zones.count else { return }
        transform(&workspaces[workspaceIndex].zones[zoneIndex])
        workspaces[workspaceIndex].zones[zoneIndex] = workspaces[workspaceIndex].zones[zoneIndex].clamped()
        markDirty()
    }

    public func addWorkspace(named name: String) {
        let workspace = Workspace(name: name)
        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
        selectedZoneIndex = nil
        markDirty()
    }

    public func renameSelectedWorkspace(to name: String) {
        guard let index = selectedWorkspaceIndex else { return }
        let old = workspaces[index].name
        workspaces[index].name = name
        if lastWorkspace.caseInsensitiveCompare(old) == .orderedSame { lastWorkspace = name }
        markDirty()
    }

    public func removeSelectedWorkspace() {
        guard let index = selectedWorkspaceIndex else { return }
        let removed = workspaces.remove(at: index)
        if lastWorkspace.caseInsensitiveCompare(removed.name) == .orderedSame { lastWorkspace = "" }
        selectedWorkspaceID = workspaces.first?.id
        selectedZoneIndex = nil
        markDirty()
    }

    public func applyPreset(_ preset: LayoutPreset) {
        guard let display = selectedDisplay else { return }
        let reference = DisplayRegistry.reference(for: display)
        mutateSelectedWorkspace { workspace in
            workspace.zones.removeAll { zone in
                DisplayRegistry.resolve(zone.monitor)?.id == display.id
            }
            workspace.zones.append(contentsOf: ZoneOps.zones(from: preset, monitor: reference))
        }
        selectedZoneIndex = selectedWorkspace?.zones.indices.last
    }

    public func splitSelectedZone(vertical: Bool) {
        guard let workspaceIndex = selectedWorkspaceIndex, let zoneIndex = selectedZoneIndex,
              zoneIndex < workspaces[workspaceIndex].zones.count else { return }
        let zone = workspaces[workspaceIndex].zones[zoneIndex]
        let halves = vertical ? ZoneOps.splitVertical(zone) : ZoneOps.splitHorizontal(zone)
        workspaces[workspaceIndex].zones.replaceSubrange(zoneIndex...zoneIndex, with: halves)
        markDirty()
    }

    public func removeSelectedZone() {
        guard let workspaceIndex = selectedWorkspaceIndex, let zoneIndex = selectedZoneIndex,
              zoneIndex < workspaces[workspaceIndex].zones.count else { return }
        workspaces[workspaceIndex].zones.remove(at: zoneIndex)
        selectedZoneIndex = workspaces[workspaceIndex].zones.isEmpty ? nil : min(zoneIndex, workspaces[workspaceIndex].zones.count - 1)
        markDirty()
    }

    public func resetSelectedDisplay() {
        guard let display = selectedDisplay else { return }
        mutateSelectedWorkspace { workspace in
            workspace.zones.removeAll { DisplayRegistry.resolve($0.monitor)?.id == display.id }
        }
        selectedZoneIndex = nil
    }

    public func renameProgram(at index: Int, to name: String) {
        guard index < programs.count else { return }
        let old = programs[index].name
        programs[index].name = name
        for workspaceIndex in workspaces.indices {
            for zoneIndex in workspaces[workspaceIndex].zones.indices
            where workspaces[workspaceIndex].zones[zoneIndex].program?.caseInsensitiveCompare(old) == .orderedSame {
                workspaces[workspaceIndex].zones[zoneIndex].program = name
            }
        }
        markDirty()
    }

    public func zoneCount(using programName: String) -> Int {
        workspaces.reduce(0) { total, workspace in
            total + workspace.zones.filter { $0.program?.caseInsensitiveCompare(programName) == .orderedSame }.count
        }
    }

    public func removeProgram(at index: Int) {
        guard index < programs.count else { return }
        let removed = programs.remove(at: index)
        for workspaceIndex in workspaces.indices {
            for zoneIndex in workspaces[workspaceIndex].zones.indices
            where workspaces[workspaceIndex].zones[zoneIndex].program?.caseInsensitiveCompare(removed.name) == .orderedSame {
                workspaces[workspaceIndex].zones[zoneIndex].program = nil
            }
        }
        markDirty()
    }

    public func moveZoneSelection(by delta: Int) {
        guard let workspace = selectedWorkspace, !workspace.zones.isEmpty else { return }
        let current = selectedZoneIndex ?? (delta > 0 ? -1 : 0)
        let count = workspace.zones.count
        selectedZoneIndex = ((current + delta) % count + count) % count
    }

    public func moveDisplaySelection(by delta: Int) {
        let displays = DisplayRegistry.current.displays
        guard displays.count > 1 else { return }
        let current = displays.firstIndex { $0.id == selectedDisplayID } ?? 0
        let count = displays.count
        selectedDisplayID = displays[((current + delta) % count + count) % count].id
    }
}
