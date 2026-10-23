import Testing
import Foundation
@testable import SlotterKit
@testable import SlotterUI

@MainActor private func editor() -> SettingsModel {
    let display = DisplayInfo(id: 1, uuid: "screen", name: "Screen",
                              frameAX: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                              workAreaAX: CGRect(x: 0, y: 30, width: 1920, height: 1050),
                              pointSize: CGSize(width: 1920, height: 1080),
                              pixelSize: CGSize(width: 3840, height: 2160), isPrimary: true, duplicateIndex: 0)
    let workspace = Workspace(name: "Test", zones: [
        Zone(monitor: MonitorRef(ordinal: 1, uuid: "screen"), x: 0, y: 0, w: 100, h: 100, program: "Browser"),
        Zone(monitor: MonitorRef(ordinal: 2, uuid: "offline"), x: 0, y: 0, w: 100, h: 100, program: "Editor")])
    return SettingsModel(config: SlotterConfig(workspaces: [workspace]),
                         snapshot: DisplaySnapshot(displays: [display], flipY: 1080), remembered: [:])
}

@Test @MainActor func gridKeepsOtherMonitorsAndProgramAssignmentsAndCanUndo() throws {
    let model = editor()
    let original = model.workspaces
    model.applyGrid(columns: 5, rows: 2)
    #expect(model.selectedWorkspace?.zones.count == 11)
    #expect(model.selectedWorkspace?.zones.first?.program == "Browser")
    #expect(model.selectedWorkspace?.zones.last == original[0].zones.last)
    model.undoLayout()
    #expect(model.workspaces == original)
    #expect(!model.dirty)
    model.redoLayout()
    #expect(model.selectedWorkspace?.zones.count == 11)
    #expect(model.dirty)
}

@Test @MainActor func fillAddsTheGapAndUndoRestoresSelection() throws {
    let model = editor()
    model.applyGrid(columns: 1, rows: 5)
    for _ in 0..<3 {
        model.selectZone(try #require(model.selectedWorkspace?.zones[1].id))
        model.deleteSelectedZone()
    }
    let priorSelection = model.selectedZoneID
    model.fillFreeSpace()
    let gap = try #require(model.selectedZone)
    #expect(gap.y == 20 && gap.h == 60)
    #expect(gap.program == nil)
    model.undoLayout()
    #expect(model.selectedZoneID == priorSelection)
    #expect(model.selectedWorkspace?.zones.count == 3)
}

@Test @MainActor func pixelEditingUsesWorkAreaAndDoesNotAlterLayoutOnUnitSwitch() throws {
    let model = editor()
    let original = model.workspaces
    model.measurementUnit = .pixels
    #expect(model.workspaces == original)
    #expect(model.displayValue(.h, for: try #require(model.selectedZone)) == 2100)
    model.setDisplayValue(.w, 768)
    #expect(model.selectedZone?.w == 20)
    model.setDisplayValue(.h, 420)
    #expect(model.selectedZone?.h == 20)
    model.selectZone(try #require(model.selectedWorkspace?.zones.last?.id))
    #expect(!model.canMeasurePixels)
    #expect(model.unitSymbol == "%")
}

@Test @MainActor func consecutiveNumericEditsUndoAsOneOperationAndNewEditClearsRedo() throws {
    let model = editor()
    model.beginGeometryEdit()
    model.setValue(.w, 9)
    model.setValue(.w, 90)
    model.endGeometryEdit()
    model.undoLayout()
    #expect(model.selectedZone?.w == 100)
    #expect(model.canRedoLayout)
    model.splitSelectedZone(vertical: true)
    #expect(!model.canRedoLayout)
}

@Test @MainActor func undoPreservesWorkspaceAndProgramRenames() throws {
    let model = editor()
    let browser = Program(name: "Browser", path: "/Applications/Browser.app")
    model.programs = [browser]
    model.applyGrid(columns: 5, rows: 2)
    model.beginRename()
    model.renaming?.value = "Renamed"
    model.commitRename()
    model.renameProgram(browser.id, to: "Web")
    model.undoLayout()
    #expect(model.selectedWorkspace?.name == "Renamed")
    #expect(model.selectedWorkspace?.zones.first?.program == "Web")
    model.redoLayout()
    model.selectedProgramID = browser.id
    model.removeSelectedProgram()
    model.undoLayout()
    #expect(model.selectedWorkspace?.zones.first?.program == "Web")
    #expect(model.programs.first?.name == "Web")
}

@Test @MainActor func renamingVirtualPlatePersistsItsNewName() throws {
    let monitor = MonitorRef(ordinal: 1, uuid: "screen")
    let plate = VirtualPlate(name: "Desktop 1", monitor: monitor, desktopID: "space-1")
    let workspace = Workspace(name: "Test", virtualPlates: [plate])
    var persisted: SlotterConfig?
    let model = SettingsModel(config: SlotterConfig(workspaces: [workspace]), actions: .init(save: { config in
        persisted = config
        return config
    }))

    model.renameVirtualPlate(plate.id, to: "Writing")
    model.save()

    #expect(model.selectedWorkspace?.virtualPlates.first?.name == "Writing")
    #expect(persisted?.workspaces.first?.virtualPlates.first?.name == "Writing")
}

@Test @MainActor func desktopOrdinalsBelongToTheirOwnDisplay() {
    let first = ManagedSpace(uuid: "a", id: 1, type: 0, ordinal: 1, label: "Desktop 1")
    let second = ManagedSpace(uuid: "b", id: 2, type: 0, ordinal: 1, label: "Desktop 1")
    let model = editor()
    model.status.spaceSnapshot = SpaceSnapshot(available: true, displays: [
        ManagedDisplaySpaces(displayUUID: "screen", displayName: "A", spaces: [first], currentSpaceUUID: "a"),
        ManagedDisplaySpaces(displayUUID: "second", displayName: "B", spaces: [second], currentSpaceUUID: "b")
    ])
    #expect(model.desktopOrdinal("a") == 1)
    #expect(model.desktopOrdinal("b") == 1)
    #expect(model.desktopOrdinal("deleted") == 0)
}

@Test @MainActor func addingVirtualPlateStartsEmptyUntilSetUp() throws {
    let model = editor()
    let before = try #require(model.selectedWorkspace?.zones)
    let monitor = try #require(model.desk.placements.first?.monitor)
    let desktop = ManagedSpace(uuid: "space-new", id: 42, type: 0, ordinal: 2, label: "Desktop 2")

    model.addVirtualPlate(on: monitor, desktop: desktop)

    let plate = try #require(model.selectedWorkspace?.virtualPlates.first)
    #expect(model.selectedWorkspace?.zones == before)
    #expect(model.selectedWorkspace?.zones.contains(where: { $0.plateID == plate.id }) == false)
    model.useVirtualMonitor(plate.id)
    #expect(model.selectedWorkspace?.zones.filter { $0.plateID == plate.id }.count == 1)
    #expect(model.selectedWorkspace?.zones.first(where: { $0.plateID == plate.id })?.program == nil)
}

@Test @MainActor func pinnedPlatesFollowDesktopOrderAndClosedPlatesMoveToBench() throws {
    let model = editor()
    let monitor = MonitorRef(ordinal: 1, uuid: "screen")
    let plates = [
        VirtualPlate(name: "Desktop 2", monitor: monitor, desktopID: "gone"),
        VirtualPlate(name: "Desktop 3", monitor: monitor, desktopID: "third"),
        VirtualPlate(name: "Desktop 2", monitor: monitor, desktopID: "first"),
        VirtualPlate(name: "Writing", monitor: monitor, desktopID: "second"),
        VirtualPlate(name: "Bench", monitor: monitor, desktopID: nil)
    ]
    model.workspaces[0].virtualPlates = plates
    model.status.spaceSnapshot = SpaceSnapshot(available: true, displays: [
        ManagedDisplaySpaces(displayUUID: "screen", displayName: "Screen", spaces: [
            ManagedSpace(uuid: "first", id: 1, type: 0, ordinal: 1, label: "Desktop 1"),
            ManagedSpace(uuid: "second", id: 2, type: 0, ordinal: 2, label: "Desktop 2"),
            ManagedSpace(uuid: "third", id: 3, type: 0, ordinal: 3, label: "Desktop 3")
        ], currentSpaceUUID: "first")
    ])

    let ordered = model.pinnedVirtualPlates(in: try #require(model.selectedWorkspace))
    #expect(ordered.map(\.id) == [plates[2].id, plates[3].id, plates[1].id])
    #expect(ordered.map { model.virtualPlateName($0) } == ["Desktop 1", "Writing", "Desktop 3"])
    #expect(model.workspaces[0].virtualPlates[0].desktopID == nil)
    #expect(model.workspaces[0].virtualPlates[0].closedDesktopLabel == "Desktop 2")

    model.status.spaceSnapshot.displays[0].spaces.removeFirst()
    model.status.spaceSnapshot.displays[0].spaces[0].ordinal = 1
    model.status.spaceSnapshot.displays[0].spaces[1].ordinal = 2
    #expect(model.virtualPlateName(plates[1]) == "Desktop 2")
    #expect(model.virtualPlateName(plates[3]) == "Writing")
}

@Test @MainActor func deletingBenchedPlateAfterConfirmationPersistsRemoval() throws {
    let monitor = MonitorRef(ordinal: 1, uuid: "screen")
    let plate = VirtualPlate(name: "Research", monitor: monitor, desktopID: nil)
    let zone = Zone(monitor: monitor, x: 0, y: 0, w: 50, h: 100, plateID: plate.id)
    let workspace = Workspace(name: "Test", zones: [zone], virtualPlates: [plate])
    var persisted: SlotterConfig?
    let model = SettingsModel(config: SlotterConfig(workspaces: [workspace]), actions: .init(save: { config in
        persisted = config
        return config
    }))

    model.confirmDeleteBenchedPlate(plate.id)
    #expect(model.pendingConfirm?.request.heading == "Delete Research?")
    #expect(model.selectedWorkspace?.virtualPlates == [plate])
    #expect(model.selectedWorkspace?.zones == [zone])
    model.pendingConfirm?.action()
    model.save()

    #expect(model.selectedWorkspace?.virtualPlates.isEmpty == true)
    #expect(model.selectedWorkspace?.zones.isEmpty == true)
    #expect(persisted?.workspaces.first?.virtualPlates.isEmpty == true)
    #expect(persisted?.workspaces.first?.zones.isEmpty == true)
}

@Test @MainActor func deletingSelectedPlateSelectsRemainingZoneAndUndoRestoresPlateSelection() throws {
    let model = editor()
    let monitor = try #require(model.desk.placements.first?.monitor)
    model.addVirtualPlate(on: monitor, desktop: ManagedSpace(uuid: "test", id: 2, type: 0, ordinal: 2, label: "Desktop 2"))
    let plateID = try #require(model.selectedVirtualPlateID)
    model.useVirtualMonitor(plateID)
    let virtualZoneID = model.selectedZoneID
    model.benchVirtualPlate(plateID)
    model.selectVirtualPlate(plateID)
    model.confirmDeleteBenchedPlate(plateID)
    model.pendingConfirm?.action()
    #expect(model.selectedZone != nil)
    #expect(model.selectedZone?.plateID == nil)
    #expect(model.selectedVirtualPlateID == nil)
    model.undoLayout()
    #expect(model.selectedZoneID == virtualZoneID)
    #expect(model.selectedVirtualPlateID == plateID)
    model.redoLayout()
    #expect(model.selectedZone != nil)
    #expect(model.selectedZone?.plateID == nil)
}

@Test @MainActor func structuralEditStartsANewUndoStepAfterTyping() throws {
    let model = editor()
    model.beginGeometryEdit()
    model.setValue(.w, 90)
    model.splitSelectedZone(vertical: true)
    model.undoLayout()
    #expect(model.selectedWorkspace?.zones.count == 2)
    #expect(model.selectedZone?.w == 90)
    model.undoLayout()
    #expect(model.selectedZone?.w == 100)
}

@Test @MainActor func subMinimumPixelSizeIsRejectedBeforeSaving() throws {
    let model = editor()
    model.measurementUnit = .pixels
    model.setDisplayValue(.w, 1)
    #expect(!model.faults.isEmpty)
    model.save()
    #expect(model.dirty)
}

@Test @MainActor func closingFlushesAnEditBeforeTheDebounceWindow() throws {
    let model = editor()
    var persisted: SlotterConfig?
    model.actions = .init(save: { config in
        persisted = config
        return config
    })

    model.setValue(.w, 75)
    model.flushOnClose()

    #expect(persisted?.workspaces.first?.zones.first?.w == 75)
}

@Test @MainActor func undoSchedulesPersistenceOfTheRestoredLayout() async throws {
    let model = editor()
    var persisted: SlotterConfig?
    model.actions = .init(save: { config in
        persisted = config
        return config
    })
    let originalWidth = try #require(model.selectedZone?.w)

    model.setValue(.w, 70)
    model.flushOnClose()
    model.undoLayout()
    try await Task.sleep(for: .milliseconds(400))

    #expect(persisted?.workspaces.first?.zones.first?.w == originalWidth)
}

@Test @MainActor func undoingLayoutDoesNotDiscardPendingSettingsEdits() throws {
    let model = editor()
    var persisted: SlotterConfig?
    model.actions = .init(save: { config in
        persisted = config
        return config
    })

    model.toggleStartAtLogin()
    model.setValue(.w, 70)
    model.undoLayout()
    model.flushOnClose()

    #expect(persisted?.startAtLogin == true)
}

@Test @MainActor func closePersistsValidEditsWhileLeavingAnInvalidDraftUnwritten() throws {
    let model = editor()
    var persisted: SlotterConfig?
    model.actions = .init(save: { config in
        persisted = config
        return config
    })

    model.setValue(.w, 75)
    model.selectZone(try #require(model.selectedWorkspace?.zones.last?.id))
    model.setValue(.w, 0.5)
    model.flushOnClose()

    #expect(persisted?.workspaces.first?.zones.first?.w == 75)
    #expect(persisted?.workspaces.first?.zones.last?.w == 100)
    #expect(model.selectedZone?.w == 0.5)
}

@Test @MainActor func closeKeepsAValidFieldEditBesideAnInvalidFieldDraft() throws {
    let model = editor()
    var persisted: SlotterConfig?
    model.actions = .init(save: { config in
        persisted = config
        return config
    })

    model.setValue(.w, 75)
    model.setValue(.h, 0.5)
    model.flushOnClose()

    #expect(persisted?.workspaces.first?.zones.first?.w == 75)
    #expect(persisted?.workspaces.first?.zones.first?.h == 100)
}

@Test @MainActor func closeKeepsValidProgramEditsBesideAnInvalidPathDraft() {
    let program = Program(name: "Browser", path: "/usr/bin/true")
    let model = SettingsModel(config: SlotterConfig(programs: [program]))
    var persisted: SlotterConfig?
    model.actions = .init(save: { config in
        persisted = config
        return config
    })

    model.updateProgram(program.id) { item in
        item.arguments = "--new-window"
        item.path = "/missing/browser"
    }
    model.flushOnClose()

    #expect(persisted?.programs.first?.arguments == "--new-window")
    #expect(persisted?.programs.first?.path == "/usr/bin/true")
}

@Test @MainActor func workspaceRemovalRequiresConfirmationAndCanBeUndone() throws {
    let model = editor()
    var persisted: SlotterConfig?
    model.actions = .init(save: { config in
        persisted = config
        return config
    })
    let original = try #require(model.selectedWorkspace)

    model.removeSelectedWorkspace()
    #expect(model.selectedWorkspace == original)
    #expect(model.pendingConfirm?.request.heading == "Remove Test?")
    model.pendingConfirm?.action()
    model.flushOnClose()
    #expect(persisted?.workspaces.isEmpty == true)

    model.undoLayout()
    model.flushOnClose()
    #expect(model.selectedWorkspace == original)
    #expect(persisted?.workspaces == [original])
}

@Test @MainActor func removingAProgramPreservesItsAssignmentsInUndoHistory() throws {
    let model = editor()
    let browser = Program(name: "Browser", path: "/usr/bin/true")
    model.programs = [browser]
    model.selectedProgramID = browser.id

    model.removeSelectedProgram()
    #expect(model.programs.isEmpty)
    #expect(model.selectedWorkspace?.zones.first?.program == nil)
    #expect(model.selectedWorkspace?.zones.last?.program == "Editor")

    model.undoLayout()
    #expect(model.programs == [browser])
    #expect(model.selectedWorkspace?.zones.first?.program == "Browser")
}
