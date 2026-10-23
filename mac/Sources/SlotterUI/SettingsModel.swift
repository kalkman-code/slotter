import AppKit
import Observation
import SlotterKit

/// The designer's working state. Valid edits are persisted as they are made.
@MainActor
@Observable
public final class SettingsModel {
    public enum Face: Sendable { case zone, settings, shortcuts }
    public enum Field: Sendable, CaseIterable { case x, y, w, h }
    public enum MeasurementUnit: Sendable { case percent, pixels }
    public enum FocusTarget: Equatable, Sendable { case rename, field(Field), programPath(UUID) }

    public struct Renaming: Equatable, Sendable {
        public var workspaceID: UUID
        public var value: String

        public init(workspaceID: UUID, value: String) {
            self.workspaceID = workspaceID
            self.value = value
        }
    }

    /// What the settings face reports about the running app, pushed in by `AppController`.
    public struct Status: Sendable {
        public var accessibilityTrusted: Bool
        public var shortcutCount: Int
        public var shortcutFailures: Int
        public var loginNeedsApproval: Bool
        public var unavailableShortcuts: [String]
        public var spaceSnapshot: SpaceSnapshot
        public var automaticUpdates: Bool
        public var canCheckForUpdates: Bool

        public init(accessibilityTrusted: Bool = true, shortcutCount: Int = 0, shortcutFailures: Int = 0,
                    loginNeedsApproval: Bool = false, unavailableShortcuts: [String] = [],
                    spaceSnapshot: SpaceSnapshot = SpaceSnapshot(available: false),
                    automaticUpdates: Bool = true, canCheckForUpdates: Bool = false) {
            self.accessibilityTrusted = accessibilityTrusted
            self.shortcutCount = shortcutCount
            self.shortcutFailures = shortcutFailures
            self.loginNeedsApproval = loginNeedsApproval
            self.unavailableShortcuts = unavailableShortcuts
            self.spaceSnapshot = spaceSnapshot
            self.automaticUpdates = automaticUpdates
            self.canCheckForUpdates = canCheckForUpdates
        }
    }

    public struct Actions {
        public var save: (SlotterConfig) -> SlotterConfig?
        public var setWorkspace: (Workspace) -> Void
        public var openAccessibilitySettings: () -> Void
        public var openLoginItemsSettings: () -> Void
        public var setAutomaticUpdates: (Bool) -> Void
        public var checkForUpdates: () -> Void

        public init(save: @escaping (SlotterConfig) -> SlotterConfig? = { $0 },
                    setWorkspace: @escaping (Workspace) -> Void = { _ in },
                    openAccessibilitySettings: @escaping () -> Void = {},
                    openLoginItemsSettings: @escaping () -> Void = {},
                    setAutomaticUpdates: @escaping (Bool) -> Void = { _ in },
                    checkForUpdates: @escaping () -> Void = {}) {
            self.save = save
            self.setWorkspace = setWorkspace
            self.openAccessibilitySettings = openAccessibilitySettings
            self.openLoginItemsSettings = openLoginItemsSettings
            self.setAutomaticUpdates = setAutomaticUpdates
            self.checkForUpdates = checkForUpdates
        }
    }

    public enum ZoneFault: Equatable, Sendable {
        case empty
        case negative
        case pastRight(Double)
        case pastBottom(Double)
    }

    public struct Fault: Sendable {
        public enum Kind: Sendable { case name, zone(workspace: UUID, zone: UUID), program(UUID) }
        public var kind: Kind
        public var message: String
    }

    public var workspaces: [Workspace]
    public var programs: [Program]
    public var desktopSetups: [DesktopSetup]
    public var lastWorkspace: String
    public var startAtLogin: Bool
    public var shortcuts: [String: String]

    public var snapshot: DisplaySnapshot
    public var remembered: [String: RememberedMonitor]
    public var status: Status {
        didSet { reconcileDesktops() }
    }
    public var actions: Actions

    public var selectedWorkspaceID: UUID?
    public var selectedZoneID: UUID?
    public var face: Face?
    public var renaming: Renaming?
    public var showingPrograms = false
    public var showingVirtualChoices = false
    public var selectedVirtualMonitorID: String?
    public var selectedVirtualPlateID: UUID?
    public var selectedBenchedPlateID: UUID?
    public var focusVirtualPlateName = false
    public var desktopSwitchMessage: String?
    public var selectedProgramID: UUID?
    public var pendingConfirm: PendingConfirm?
    public var focusRequest: FocusTarget?
    public var measurementUnit: MeasurementUnit = .percent

    private struct LayoutState {
        var workspaces: [Workspace]
        var programs: [Program]
        var lastWorkspace: String
        var selectedWorkspaceID: UUID?
        var selectedZoneID: UUID?
        var selectedVirtualPlateID: UUID?
        var selectedProgramID: UUID?
        var face: Face?
    }
    private var undoStates: [LayoutState] = []
    private var redoStates: [LayoutState] = []
    private var editingGeometry = false
    private var recordedEdit = false
    private var persistenceWork: DispatchWorkItem?

    public var canUndoLayout: Bool { !undoStates.isEmpty }
    public var canRedoLayout: Bool { !redoStates.isEmpty }

    private func recordLayout(grouped: Bool = false) {
        if !grouped { endGeometryEdit() }
        guard !editingGeometry || !recordedEdit else { return }
        undoStates.append(captureLayout())
        if undoStates.count > 100 { undoStates.removeFirst() }
        redoStates.removeAll()
        recordedEdit = true
    }

    private func captureLayout() -> LayoutState {
        LayoutState(workspaces: workspaces, programs: programs, lastWorkspace: lastWorkspace,
                    selectedWorkspaceID: selectedWorkspaceID, selectedZoneID: selectedZoneID,
                    selectedVirtualPlateID: selectedVirtualPlateID,
                    selectedProgramID: selectedProgramID, face: face)
    }

    public func beginGeometryEdit() { editingGeometry = true; recordedEdit = false }
    public func endGeometryEdit() { editingGeometry = false; recordedEdit = false }

    private func clearLayoutHistory() {
        undoStates.removeAll()
        redoStates.removeAll()
        endGeometryEdit()
    }

    private func restoreLayout(_ state: LayoutState) {
        workspaces = state.workspaces
        programs = state.programs
        lastWorkspace = state.lastWorkspace
        selectedWorkspaceID = state.selectedWorkspaceID
        selectedZoneID = state.selectedZoneID
        selectedVirtualPlateID = state.selectedVirtualPlateID
        selectedProgramID = state.selectedProgramID
        face = state.face
        endGeometryEdit()
        if workspaces == original.workspaces && programs == original.programs
            && lastWorkspace == original.lastWorkspace && startAtLogin == original.startAtLogin
            && shortcuts == original.shortcuts && desktopSetups == original.desktopSetups {
            persistenceWork?.cancel()
            dirty = false
            saved = false
        } else {
            touch()
        }
    }

    public func undoLayout() {
        guard let state = undoStates.popLast() else { return }
        redoStates.append(captureLayout())
        restoreLayout(state)
    }

    public func redoLayout() {
        guard let state = redoStates.popLast() else { return }
        undoStates.append(captureLayout())
        restoreLayout(state)
    }

    public private(set) var dirty = false
    public private(set) var saved = false

    private var original: SlotterConfig

    public static let designerPresets = ["Full", "2 columns", "3 columns", "4 columns", "2 rows", "3 rows",
                                         "2 × 2 grid", "Left ⅔ + right ⅓", "Left ⅓ + right ⅔"]
        .compactMap { name in PresetCatalog.all.first { $0.name == name } }

    public init(config: SlotterConfig, snapshot: DisplaySnapshot = DisplayRegistry.current,
                remembered: [String: RememberedMonitor] = MonitorMemory.load(),
                status: Status = Status(), actions: Actions = Actions()) {
        self.remembered = remembered
        original = config
        workspaces = config.workspaces
        programs = config.programs
        desktopSetups = config.desktopSetups
        lastWorkspace = config.lastWorkspace
        startAtLogin = config.startAtLogin
        shortcuts = config.shortcuts
        self.snapshot = snapshot
        self.status = status
        self.actions = actions
        let first = config.workspace(named: config.lastWorkspace) ?? config.workspaces.first
        selectedWorkspaceID = first?.id
        selectedZoneID = first?.zones.first?.id
        face = first == nil ? nil : .zone
        selectedProgramID = config.programs.first?.id
        reconcileDesktops()
    }

    public var config: SlotterConfig {
        SlotterConfig(workspaces: workspaces, programs: programs, lastWorkspace: lastWorkspace,
                      startAtLogin: startAtLogin, shortcuts: shortcuts, desktopSetups: desktopSetups)
    }

    // MARK: - Lookup

    public var desk: DeskArrangement {
        let references = workspaces.flatMap { workspace in
            workspace.zones.map(\.monitor) + workspace.virtualPlates.map(\.monitor)
        }
        return DeskPlanner.arrange(snapshot, references: references, remembered: remembered)
    }

    public var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceID }
    }

    private var selectedWorkspaceIndex: Int? {
        workspaces.firstIndex { $0.id == selectedWorkspaceID }
    }

    public var selectedZone: Zone? {
        selectedWorkspace?.zones.first { $0.id == selectedZoneID }
    }

    public func monitorKey(_ zone: Zone) -> String {
        DeskPlanner.key(for: zone.monitor, in: snapshot)
    }

    public func monitorKeyFor(_ monitor: MonitorRef) -> String {
        DeskPlanner.key(for: monitor, in: snapshot)
    }

    public func number(of zone: Zone, in workspace: Workspace) -> Int {
        (workspace.zones.firstIndex { $0.id == zone.id } ?? 0) + 1
    }

    /// The monitors a workspace uses, in desk order.
    public func monitorKeys(of workspace: Workspace, in desk: DeskArrangement) -> [String] {
        let used = Set(workspace.zones.map(monitorKey))
        return desk.monitors.map(\.id).filter(used.contains)
    }

    public func isOffline(_ key: String) -> Bool { key.hasPrefix("offline:") }

    public func isFullyOffline(_ workspace: Workspace) -> Bool {
        let keys = Set(workspace.zones.map(monitorKey))
        return !keys.isEmpty && keys.allSatisfy(isOffline)
    }

    public func program(named name: String?) -> Program? {
        guard let name, !name.isEmpty else { return nil }
        return programs.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Workspaces grouped by the set of monitors each uses, groups in order of first appearance.
    public func groups(in desk: DeskArrangement) -> [(keys: [String], workspaces: [Workspace])] {
        var result: [(keys: [String], workspaces: [Workspace])] = []
        for workspace in workspaces {
            let keys = monitorKeys(of: workspace, in: desk)
            if let index = result.firstIndex(where: { $0.keys == keys }) {
                result[index].workspaces.append(workspace)
            } else {
                result.append((keys, [workspace]))
            }
        }
        return result
    }

    public func presetMatch(on key: String, in workspace: Workspace) -> LayoutPreset? {
        let zones = workspace.zones.filter { monitorKey($0) == key && $0.plateID == selectedZone?.plateID }
        return Self.designerPresets.first { preset in
            preset.zones.count == zones.count && preset.zones.allSatisfy { fraction in
                zones.contains {
                    abs($0.x - fraction.x) < 0.2 && abs($0.y - fraction.y) < 0.2
                        && abs($0.w - fraction.w) < 0.2 && abs($0.h - fraction.h) < 0.2
                }
            }
        }
    }

    // MARK: - Validation

    public func fault(of zone: Zone) -> ZoneFault? {
        if zone.w < 1 || zone.h < 1 { return .empty }
        if zone.x < 0 || zone.y < 0 { return .negative }
        if zone.x + zone.w > 100.05 { return .pastRight(zone.x + zone.w - 100) }
        if zone.y + zone.h > 100.05 { return .pastBottom(zone.y + zone.h - 100) }
        return nil
    }

    public var renameError: String? {
        guard let renaming else { return nil }
        let own = workspaces.first { $0.id == renaming.workspaceID }
        return Validate.workspaceName(renaming.value, excluding: own, in: workspaces)
    }

    public var faults: [Fault] {
        var result: [Fault] = []
        if let error = renameError { result.append(Fault(kind: .name, message: error)) }
        for workspace in workspaces {
            for zone in workspace.zones {
                guard let fault = fault(of: zone) else { continue }
                let number = number(of: zone, in: workspace)
                let message: String
                switch fault {
                case .empty: message = "\(workspace.name) zone \(number) must be at least 1% wide and high"
                case .negative: message = "\(workspace.name) zone \(number) starts off the screen"
                case .pastRight: message = "\(workspace.name) zone \(number) runs past the right edge"
                case .pastBottom: message = "\(workspace.name) zone \(number) runs past the bottom edge"
                }
                result.append(Fault(kind: .zone(workspace: workspace.id, zone: zone.id), message: message))
            }
        }
        for program in programs where program.path.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(Fault(kind: .program(program.id), message: "Choose an application for \(program.name)"))
        }
        return result
    }

    public func gotoFirstFault() {
        guard let first = faults.first else { return }
        switch first.kind {
        case .name:
            focusRequest = .rename
        case let .zone(workspaceID, zoneID):
            showingPrograms = false
            if selectedWorkspaceID != workspaceID { clearLayoutHistory() }
            selectedWorkspaceID = workspaceID
            selectedZoneID = zoneID
            face = .zone
            guard let zone = selectedZone else { return }
            switch fault(of: zone) {
            case .pastRight: focusRequest = .field(.w)
            case .pastBottom: focusRequest = .field(.h)
            default: focusRequest = .field(.x)
            }
        case let .program(id):
            selectedProgramID = id
            showingPrograms = true
            focusRequest = .programPath(id)
        }
    }

    // MARK: - Commit

    private func touch() {
        dirty = true
        saved = false
        persistenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.persistCurrentConfig()
        }
        persistenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func persistableConfig() -> SlotterConfig {
        var candidate = config
        for workspaceIndex in candidate.workspaces.indices {
            for zoneIndex in candidate.workspaces[workspaceIndex].zones.indices.reversed() {
                let zone = candidate.workspaces[workspaceIndex].zones[zoneIndex]
                guard fault(of: zone) != nil else { continue }
                if let previous = original.workspaces.first(where: { $0.id == candidate.workspaces[workspaceIndex].id })?
                    .zones.first(where: { $0.id == zone.id }) {
                    var safe = zone
                    if safe.x < 0 { safe.x = previous.x }
                    if safe.y < 0 { safe.y = previous.y }
                    if safe.w < 1 { safe.w = previous.w }
                    if safe.h < 1 { safe.h = previous.h }
                    if safe.x + safe.w > 100.05 {
                        let resetX = safe.x
                        safe.x = previous.x
                        if fault(of: safe) != nil {
                            safe.x = resetX
                            safe.w = previous.w
                        }
                    }
                    if safe.y + safe.h > 100.05 {
                        let resetY = safe.y
                        safe.y = previous.y
                        if fault(of: safe) != nil {
                            safe.y = resetY
                            safe.h = previous.h
                        }
                    }
                    candidate.workspaces[workspaceIndex].zones[zoneIndex] = fault(of: safe) == nil ? safe : previous
                } else {
                    candidate.workspaces[workspaceIndex].zones.remove(at: zoneIndex)
                }
            }
        }
        for index in candidate.programs.indices.reversed()
        where Validate.programPath(candidate.programs[index].path) != nil {
            if let previous = original.programs.first(where: { $0.id == candidate.programs[index].id }) {
                candidate.programs[index].path = previous.path
            } else {
                candidate.programs.remove(at: index)
            }
        }
        return candidate
    }

    @discardableResult
    private func persistCurrentConfig() -> SlotterConfig? {
        guard let stored = actions.save(persistableConfig()) else { return nil }
        original = stored
        dirty = !faults.isEmpty
        saved = !dirty
        return stored
    }

    public func save() {
        guard dirty else { return }
        persistenceWork?.cancel()
        guard let stored = persistCurrentConfig() else { return }
        startAtLogin = stored.startAtLogin
        if !faults.isEmpty { gotoFirstFault() }
    }

    public func flushOnClose() {
        if renaming != nil { commitRename() }
        save()
    }

    public func toggleStartAtLogin() {
        startAtLogin.toggle()
        touch()
    }

    public func setShortcut(_ action: SnapAction, combo: KeyCombo?) {
        shortcuts[action.rawValue] = combo.map(\.display) ?? "none"
        touch()
    }

    public func resetShortcut(_ action: SnapAction) {
        shortcuts.removeValue(forKey: action.rawValue)
        touch()
    }

    public func resetShortcuts() {
        guard !shortcuts.isEmpty else { return }
        shortcuts.removeAll()
        touch()
    }

    public func cancel() {
        clearLayoutHistory()
        workspaces = original.workspaces
        programs = original.programs
        desktopSetups = original.desktopSetups
        lastWorkspace = original.lastWorkspace
        startAtLogin = original.startAtLogin
        shortcuts = original.shortcuts
        renaming = nil
        dirty = false
        if selectedWorkspace == nil { selectedWorkspaceID = workspaces.first?.id }
        if selectedZone == nil { selectedZoneID = selectedWorkspace?.zones.first?.id }
        if programs.first(where: { $0.id == selectedProgramID }) == nil { selectedProgramID = programs.first?.id }
        if selectedWorkspace == nil, face == .zone { face = nil }
    }

    // MARK: - Workspaces

    public func selectWorkspace(_ id: UUID) {
        clearLayoutHistory()
        selectedWorkspaceID = id
        selectedVirtualPlateID = nil
        selectedZoneID = selectedWorkspace?.zones.first?.id
        if face != .settings { face = selectedZoneID == nil ? nil : .zone }
    }

    public func selectZone(_ id: UUID) {
        endGeometryEdit()
        selectedZoneID = id
        selectedVirtualPlateID = selectedWorkspace?.zones.first(where: { $0.id == id })?.plateID
        face = .zone
    }

    public func toggleFace(_ target: Face) {
        face = face == target ? nil : target
    }

    /// One full zone on every connected monitor, then straight into rename.
    public func addWorkspace() {
        clearLayoutHistory()
        var index = 1
        while workspaces.contains(where: { $0.name.caseInsensitiveCompare("Workspace \(index)") == .orderedSame }) {
            index += 1
        }
        let zones = snapshot.ordered().map {
            Zone(monitor: DisplayRegistry.reference(for: $0, in: snapshot), x: 0, y: 0, w: 100, h: 100)
        }
        let workspace = Workspace(name: "Workspace \(index)", zones: zones)
        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
        selectedZoneID = zones.first?.id
        face = zones.isEmpty ? nil : .zone
        renaming = Renaming(workspaceID: workspace.id, value: workspace.name)
        focusRequest = .rename
        touch()
    }

    public func beginRename() {
        guard let workspace = selectedWorkspace else { return }
        renaming = Renaming(workspaceID: workspace.id, value: workspace.name)
        focusRequest = .rename
    }

    public func commitRename() {
        guard let renaming, renameError == nil,
              let index = workspaces.firstIndex(where: { $0.id == renaming.workspaceID }) else { return }
        let name = renaming.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let old = workspaces[index].name
        self.renaming = nil
        guard name != old else { return }
        workspaces[index].name = name
        if lastWorkspace.caseInsensitiveCompare(old) == .orderedSame { lastWorkspace = name }
        updateHistoryWorkspace(old, to: name)
        touch()
    }

    public func cancelRename() {
        renaming = nil
    }

    public func removeSelectedWorkspace() {
        guard let workspace = selectedWorkspace else { return }
        confirm(ConfirmRequest(heading: "Remove \(workspace.name)?",
                               body: "Its plates and zones will be removed. You can undo this removal.",
                               confirmTitle: "Remove", danger: true)) { [weak self] in
            self?.removeWorkspace(workspace.id)
        }
    }

    private func removeWorkspace(_ id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        recordLayout()
        let removed = workspaces.remove(at: index)
        if renaming?.workspaceID == removed.id { renaming = nil }
        if lastWorkspace.caseInsensitiveCompare(removed.name) == .orderedSame { lastWorkspace = "" }
        if selectedWorkspaceID == id {
            selectedWorkspaceID = workspaces.first?.id
            selectedZoneID = selectedWorkspace?.zones.first?.id
            if selectedZoneID == nil, face != .settings { face = nil }
        }
        touch()
    }

    // MARK: - Zones

    private func mutateWorkspace(_ body: (inout Workspace) -> Void) {
        guard let index = selectedWorkspaceIndex else { return }
        recordLayout()
        body(&workspaces[index])
        touch()
    }

    private func mutateZone(grouped: Bool = false, _ body: (inout Zone) -> Void) {
        guard let index = selectedWorkspaceIndex,
              let zoneIndex = workspaces[index].zones.firstIndex(where: { $0.id == selectedZoneID }) else { return }
        recordLayout(grouped: grouped)
        body(&workspaces[index].zones[zoneIndex])
        touch()
    }

    public func setValue(_ field: Field, _ value: Double) {
        guard value.isFinite else { return }
        let rounded = (value * 100).rounded() / 100
        guard let zone = selectedZone, percentValue(field, for: zone) != rounded else { return }
        mutateZone(grouped: true) { zone in
            switch field {
            case .x: zone.x = rounded
            case .y: zone.y = rounded
            case .w: zone.w = rounded
            case .h: zone.h = rounded
            }
        }
    }

    private func percentValue(_ field: Field, for zone: Zone) -> Double {
        switch field { case .x: zone.x; case .y: zone.y; case .w: zone.w; case .h: zone.h }
    }

    private var workAreaPixels: CGSize? {
        guard let zone = selectedZone, let display = DisplayRegistry.resolve(zone.monitor, in: snapshot),
              display.pointSize.width > 0, display.pointSize.height > 0 else { return nil }
        let size = CGSize(width: display.workAreaAX.width * display.pixelSize.width / display.pointSize.width,
                          height: display.workAreaAX.height * display.pixelSize.height / display.pointSize.height)
        return size.width > 0 && size.height > 0 ? size : nil
    }

    public var canMeasurePixels: Bool { workAreaPixels != nil }
    public var unitSymbol: String { measurementUnit == .pixels && canMeasurePixels ? "px" : "%" }

    public func displayValue(_ field: Field, for zone: Zone) -> Double {
        let value = percentValue(field, for: zone)
        guard measurementUnit == .pixels, let size = workAreaPixels else { return value }
        return value * (field == .x || field == .w ? size.width : size.height) / 100
    }

    public func setDisplayValue(_ field: Field, _ value: Double) {
        guard measurementUnit == .pixels, let size = workAreaPixels else { setValue(field, value); return }
        setValue(field, value * 100 / (field == .x || field == .w ? size.width : size.height))
    }

    public func applyGrid(columns: Int, rows: Int) {
        guard let preset = PresetCatalog.grid(columns: columns, rows: rows) else { return }
        applyPreset(preset)
    }

    public var freeSpace: ZoneFraction? {
        guard let zone = selectedZone, let workspace = selectedWorkspace else { return nil }
        return ZoneOps.largestFreeSpace(among: workspace.zones.filter { samePlate($0, zone) })
    }

    private func samePlate(_ candidate: Zone, _ selected: Zone) -> Bool {
        monitorKey(candidate) == monitorKey(selected) && candidate.plateID == selected.plateID
    }

    public func fillFreeSpace() {
        guard let zone = selectedZone, let gap = freeSpace else { return }
        let added = Zone(monitor: zone.monitor, x: gap.x, y: gap.y, w: gap.w, h: gap.h, plateID: zone.plateID)
        mutateWorkspace { $0.zones.append(added) }
        selectedZoneID = added.id
        face = .zone
    }

    public func fitSelectedZone() {
        mutateZone { zone in
            if zone.x + zone.w > 100 { zone.w = ((100 - zone.x) * 100).rounded() / 100 }
            if zone.y + zone.h > 100 { zone.h = ((100 - zone.y) * 100).rounded() / 100 }
        }
    }

    public func assignProgram(_ name: String?) {
        mutateZone { $0.program = (name?.isEmpty ?? true) ? nil : name }
    }

    public func splitSelectedZone(vertical: Bool) {
        guard let zone = selectedZone else { return }
        guard vertical ? zone.isSplittableHorizontally : zone.isSplittableVertically else { return }
        let halves = vertical ? ZoneOps.splitVertical(zone) : ZoneOps.splitHorizontal(zone)
        mutateWorkspace { workspace in
            guard let index = workspace.zones.firstIndex(where: { $0.id == zone.id }) else { return }
            workspace.zones.replaceSubrange(index...index, with: halves)
        }
        selectedZoneID = halves.last?.id
        face = .zone
    }

    public func canDeleteSelectedZone() -> Bool {
        guard let zone = selectedZone, let workspace = selectedWorkspace else { return false }
        return workspace.zones.filter { samePlate($0, zone) }.count > 1
    }

    public func deleteSelectedZone() {
        guard canDeleteSelectedZone(), let zone = selectedZone else { return }
        mutateWorkspace { $0.zones.removeAll { $0.id == zone.id } }
        selectedZoneID = selectedWorkspace?.zones.first { samePlate($0, zone) }?.id
    }

    /// Replaces every zone on the selected zone's monitor, carrying the apps across in reading order.
    public func applyPreset(_ preset: LayoutPreset) {
        guard let zone = selectedZone else { return }
        var made: [Zone] = []
        mutateWorkspace { workspace in
            let old = workspace.zones.filter { samePlate($0, zone) }
                .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            let at = workspace.zones.firstIndex { samePlate($0, zone) } ?? workspace.zones.count
            made = ZoneOps.zones(from: preset, monitor: zone.monitor)
            for index in made.indices { made[index].plateID = zone.plateID }
            for index in made.indices where index < old.count { made[index].program = old[index].program }
            workspace.zones.removeAll { samePlate($0, zone) }
            workspace.zones.insert(contentsOf: made, at: min(at, workspace.zones.count))
        }
        selectedZoneID = made.first?.id
    }

    public func resetSelectedMonitor() {
        guard let zone = selectedZone else { return }
        let keep = selectedWorkspace?.zones.first { samePlate($0, zone) && $0.program != nil }?.program
        let full = Zone(monitor: zone.monitor, x: 0, y: 0, w: 100, h: 100, program: keep, plateID: zone.plateID)
        mutateWorkspace { workspace in
            workspace.zones.removeAll { samePlate($0, zone) }
            workspace.zones.append(full)
        }
        selectedZoneID = full.id
    }

    public func canStopUsingSelectedMonitor() -> Bool {
        guard let workspace = selectedWorkspace else { return false }
        return Set(workspace.zones.map { "\(monitorKey($0)):\($0.plateID?.uuidString ?? "physical")" }).count > 1
    }

    public func stopUsingSelectedMonitor() {
        guard canStopUsingSelectedMonitor(), let zone = selectedZone else { return }
        mutateWorkspace { $0.zones.removeAll { samePlate($0, zone) } }
        selectedZoneID = selectedWorkspace?.zones.first?.id
    }

    public func useMonitor(_ monitor: DeskMonitor) {
        let zone = Zone(monitor: monitor.reference, x: 0, y: 0, w: 100, h: 100)
        mutateWorkspace { $0.zones.append(zone) }
        selectedZoneID = zone.id
        face = .zone
    }

    public func addVirtualPlate(on monitor: DeskMonitor, desktop: ManagedSpace) {
        guard let workspaceIndex = selectedWorkspaceIndex else { return }
        let reference = monitor.reference
        let plate = VirtualPlate(name: desktop.label, monitor: reference, desktopID: desktop.uuid)
        recordLayout()
        workspaces[workspaceIndex].virtualPlates.append(plate)
        selectedVirtualPlateID = plate.id
        selectedZoneID = nil
        face = .settings
        selectedVirtualMonitorID = nil
        showingVirtualChoices = false
        touch()
    }

    public func useVirtualMonitor(_ plateID: UUID) {
        guard let workspaceIndex = selectedWorkspaceIndex,
              let plate = workspaces[workspaceIndex].virtualPlates.first(where: { $0.id == plateID }),
              !workspaces[workspaceIndex].zones.contains(where: { $0.plateID == plateID }) else { return }
        let zone = Zone(monitor: plate.monitor, x: 0, y: 0, w: 100, h: 100, plateID: plateID)
        mutateWorkspace { $0.zones.append(zone) }
        selectedVirtualPlateID = plateID
        selectedZoneID = zone.id
        face = .zone
    }

    public func benchVirtualPlate(_ id: UUID) {
        guard let workspaceIndex = selectedWorkspaceIndex,
              let index = workspaces[workspaceIndex].virtualPlates.firstIndex(where: { $0.id == id }) else { return }
        recordLayout()
        workspaces[workspaceIndex].virtualPlates[index].desktopID = nil
        if selectedVirtualPlateID == id { selectedVirtualPlateID = nil }
        touch()
    }

    private func reconcileDesktops() {
        var changed = false
        for index in workspaces.indices {
            if workspaces[index].reconcileDesktops(status.spaceSnapshot) { changed = true }
        }
        if changed {
            if let id = selectedVirtualPlateID,
               selectedWorkspace?.virtualPlates.first(where: { $0.id == id })?.desktopID == nil {
                selectedVirtualPlateID = nil
                selectedZoneID = selectedWorkspace?.zones.first(where: { $0.plateID == nil })?.id
            }
            touch()
        }
    }

    public func renameVirtualPlate(_ id: UUID, to raw: String) {
        guard let workspaceIndex = selectedWorkspaceIndex,
              let index = workspaces[workspaceIndex].virtualPlates.firstIndex(where: { $0.id == id }) else { return }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, workspaces[workspaceIndex].virtualPlates[index].name != name
                || workspaces[workspaceIndex].virtualPlates[index].followsDesktopName else { return }
        recordLayout()
        workspaces[workspaceIndex].virtualPlates[index].name = name
        workspaces[workspaceIndex].virtualPlates[index].followsDesktopName = false
        touch()
    }

    public func confirmDeleteBenchedPlate(_ id: UUID) {
        guard let plate = selectedWorkspace?.virtualPlates.first(where: { $0.id == id }), plate.desktopID == nil else { return }
        confirm(ConfirmRequest(heading: "Delete \(plate.name)?",
                               body: "This removes the saved plate and its zones from this workspace.",
                               confirmTitle: "Delete plate", danger: true)) { [weak self] in
            guard let self, let workspaceIndex = self.selectedWorkspaceIndex else { return }
            self.recordLayout()
            self.workspaces[workspaceIndex].virtualPlates.removeAll { $0.id == id }
            self.workspaces[workspaceIndex].zones.removeAll { $0.plateID == id }
            if self.selectedZone == nil {
                self.selectedZoneID = self.selectedWorkspace?.zones.first?.id
                self.selectedVirtualPlateID = self.selectedZone?.plateID
            }
            if self.selectedVirtualPlateID == id { self.selectedVirtualPlateID = nil }
            if self.selectedBenchedPlateID == id { self.selectedBenchedPlateID = nil }
            self.touch()
        }
    }

    public func selectVirtualPlate(_ id: UUID?) {
        selectedVirtualPlateID = id
        if let id, let workspace = selectedWorkspace {
            selectedZoneID = workspace.zones.first(where: { $0.plateID == id })?.id
            face = selectedZoneID == nil ? .settings : .zone
        }
    }

    public func desktopOrdinal(_ id: String?) -> Int {
        guard let id else { return 0 }
        let spaces = status.spaceSnapshot.displays.flatMap(\.spaces).filter { !$0.isFullscreen }
        return spaces.first(where: { $0.uuid == id })?.ordinal ?? 0
    }

    public func desktopDescription(_ plate: VirtualPlate) -> String {
        let ordinal = desktopOrdinal(plate.desktopID)
        return ordinal > 0 ? "macOS Desktop \(ordinal)" : plate.desktopID == nil ? "Bench" : "Desktop unavailable"
    }

    public func showDesktop(_ plate: VirtualPlate) {
        desktopSwitchMessage = DesktopSwitcher.show(plate)
        guard desktopSwitchMessage == nil, let id = plate.desktopID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            let snapshot = SpaceRegistry.shared.snapshot()
            guard let self else { return }
            self.status.spaceSnapshot = snapshot
            if !snapshot.displays.contains(where: { $0.currentSpaceUUID == id }) {
                self.desktopSwitchMessage = "macOS did not switch desktops. Check the Mission Control shortcut for this desktop and try again."
            }
        }
    }

    public func saveDesktopSetup(_ plateID: UUID, name raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 48,
              name.rangeOfCharacter(from: CharacterSet(charactersIn: "[]=,").union(.controlCharacters)) == nil else {
            return "Use a name of 1–48 characters without [ ] = , or line breaks."
        }
        guard !desktopSetups.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return "A setup with that name already exists. Choose another name."
        }
        guard let workspace = selectedWorkspace else { return "Select a virtual plate first." }
        let zones = workspace.zones.filter { $0.plateID == plateID }
        guard !zones.isEmpty else { return "Set up zones on this plate before saving a setup." }
        guard zones.allSatisfy({ fault(of: $0) == nil }) else { return "Fix this plate’s zone measurements before saving a setup." }
        desktopSetups.append(DesktopSetup(name: name, zones: zones.map {
            Zone(monitor: MonitorRef(ordinal: 1), x: $0.x, y: $0.y, w: $0.w, h: $0.h, program: $0.program).clamped()
        }))
        touch()
        return nil
    }

    public func loadDesktopSetup(_ setup: DesktopSetup, onto plateID: UUID) {
        guard let index = selectedWorkspaceIndex,
              let plate = workspaces[index].virtualPlates.first(where: { $0.id == plateID }) else { return }
        recordLayout()
        let zones = setup.zones.map {
            Zone(monitor: plate.monitor, x: $0.x, y: $0.y, w: $0.w, h: $0.h,
                 program: $0.program.flatMap { name in programs.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame } ? name : nil }, plateID: plateID)
        }
        workspaces[index].zones.removeAll { $0.plateID == plateID }
        workspaces[index].zones.append(contentsOf: zones)
        selectedVirtualPlateID = plateID
        selectedZoneID = zones.first?.id
        face = .zone
        touch()
    }

    public func pinnedVirtualPlates(in workspace: Workspace) -> [VirtualPlate] {
        workspace.virtualPlates.enumerated().filter { $0.element.desktopID != nil }.sorted {
            let left = desktopOrdinal($0.element.desktopID)
            let right = desktopOrdinal($1.element.desktopID)
            let a = left > 0 ? left : Int.max
            let b = right > 0 ? right : Int.max
            return a == b ? $0.offset < $1.offset : a < b
        }.map(\.element)
    }

    public func virtualPlateName(_ plate: VirtualPlate) -> String {
        guard plate.desktopID != nil, plate.followsDesktopName else { return plate.name }
        let ordinal = desktopOrdinal(plate.desktopID)
        return ordinal > 0 ? "Desktop \(ordinal)" : "Saved \(plate.name)"
    }

    public func pinVirtualPlate(_ id: UUID, to desktop: ManagedSpace) {
        guard let workspaceIndex = selectedWorkspaceIndex,
              let index = workspaces[workspaceIndex].virtualPlates.firstIndex(where: { $0.id == id }) else { return }
        let monitorID = DeskPlanner.key(for: workspaces[workspaceIndex].virtualPlates[index].monitor, in: snapshot)
        guard !workspaces[workspaceIndex].virtualPlates.contains(where: {
            $0.id != id && $0.desktopID == desktop.uuid
                && DeskPlanner.key(for: $0.monitor, in: snapshot) == monitorID
        }) else { return }
        recordLayout()
        workspaces[workspaceIndex].virtualPlates[index].desktopID = desktop.uuid
        workspaces[workspaceIndex].virtualPlates[index].closedDesktopLabel = nil
        if workspaces[workspaceIndex].virtualPlates[index].followsDesktopName {
            workspaces[workspaceIndex].virtualPlates[index].name = desktop.label
        }
        touch()
    }

    public func moveZoneSelection(by delta: Int) {
        guard let workspace = selectedWorkspace, !workspace.zones.isEmpty else { return }
        let current = workspace.zones.firstIndex { $0.id == selectedZoneID } ?? (delta > 0 ? -1 : 0)
        let count = workspace.zones.count
        selectedZoneID = workspace.zones[((current + delta) % count + count) % count].id
        face = .zone
    }

    // MARK: - Programs

    public func zoneUses(of program: Program) -> [String] {
        workspaces.flatMap { workspace in
            workspace.zones.enumerated().compactMap { index, zone in
                zone.program?.caseInsensitiveCompare(program.name) == .orderedSame
                    ? "\(workspace.name) · zone \(index + 1)" : nil
            }
        }
    }

    public func addProgram() {
        var name = "New program"
        var index = 2
        while program(named: name) != nil {
            name = "New program \(index)"
            index += 1
        }
        let program = Program(name: name, path: "")
        programs.append(program)
        selectedProgramID = program.id
        touch()
    }

    public func removeSelectedProgram() {
        guard let index = programs.firstIndex(where: { $0.id == selectedProgramID }) else { return }
        recordLayout()
        let removed = programs.remove(at: index)
        for w in workspaces.indices {
            for z in workspaces[w].zones.indices
            where workspaces[w].zones[z].program?.caseInsensitiveCompare(removed.name) == .orderedSame {
                workspaces[w].zones[z].program = nil
            }
        }
        selectedProgramID = programs.isEmpty ? nil : programs[min(index, programs.count - 1)].id
        touch()
    }

    /// Applied only when valid, so a half-typed name that briefly matches another program never
    /// merges their zones. Returns the reason it was not applied.
    @discardableResult
    public func renameProgram(_ id: UUID, to raw: String) -> String? {
        guard let index = programs.firstIndex(where: { $0.id == id }) else { return nil }
        if let error = Validate.programName(raw, excluding: programs[index], in: programs) { return error }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let old = programs[index].name
        guard name != old else { return nil }
        programs[index].name = name
        updateHistoryProgram(programs[index], replacing: old)
        for setup in desktopSetups.indices {
            for zone in desktopSetups[setup].zones.indices
            where desktopSetups[setup].zones[zone].program?.caseInsensitiveCompare(old) == .orderedSame {
                desktopSetups[setup].zones[zone].program = name
            }
        }
        for w in workspaces.indices {
            for z in workspaces[w].zones.indices
            where workspaces[w].zones[z].program?.caseInsensitiveCompare(old) == .orderedSame {
                workspaces[w].zones[z].program = name
            }
        }
        touch()
        return nil
    }

    public func updateProgram(_ id: UUID, _ body: (inout Program) -> Void) {
        guard let index = programs.firstIndex(where: { $0.id == id }) else { return }
        let oldName = programs[index].name
        body(&programs[index])
        updateHistoryProgram(programs[index], replacing: oldName == programs[index].name ? nil : oldName)
        touch()
    }

    private func updateHistoryProgram(_ program: Program, replacing oldName: String?) {
        func update(_ state: inout LayoutState) {
            for workspace in state.workspaces.indices {
                for zone in state.workspaces[workspace].zones.indices
                where oldName.map({ state.workspaces[workspace].zones[zone].program?.caseInsensitiveCompare($0) == .orderedSame }) == true {
                    state.workspaces[workspace].zones[zone].program = program.name
                }
            }
            if let index = state.programs.firstIndex(where: { $0.id == program.id }) {
                state.programs[index] = program
            }
        }
        for index in undoStates.indices { update(&undoStates[index]) }
        for index in redoStates.indices { update(&redoStates[index]) }
    }

    private func updateHistoryWorkspace(_ name: String, to newName: String) {
        func update(_ state: inout LayoutState) {
            for index in state.workspaces.indices
            where state.workspaces[index].name.caseInsensitiveCompare(name) == .orderedSame {
                state.workspaces[index].name = newName
            }
            if state.lastWorkspace.caseInsensitiveCompare(name) == .orderedSame { state.lastWorkspace = newName }
        }
        for index in undoStates.indices { update(&undoStates[index]) }
        for index in redoStates.indices { update(&redoStates[index]) }
    }

    public func confirm(_ request: ConfirmRequest, action: @escaping () -> Void) {
        pendingConfirm = PendingConfirm(request: request, action: action)
    }
}
