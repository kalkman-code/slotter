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
