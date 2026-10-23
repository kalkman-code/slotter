import Foundation
import Testing
@testable import SlotterKit
@testable import SlotterUI

@Test @MainActor func desktopSetupsLoadOntoAnotherDesktopWithoutChangingItsIdentityAndUndo() throws {
    let monitor = MonitorRef(ordinal: 1, uuid: "screen")
    let source = VirtualPlate(name: "Source", monitor: monitor, desktopID: "a")
    let target = VirtualPlate(name: "Target", monitor: monitor, desktopID: "b")
    let left = Zone(monitor: monitor, x: 0, y: 0, w: 40, h: 100, program: "Editor", plateID: source.id)
    let right = Zone(monitor: monitor, x: 40, y: 0, w: 60, h: 100, plateID: source.id)
    let existing = Zone(monitor: monitor, x: 0, y: 0, w: 100, h: 100, plateID: target.id)
    let workspace = Workspace(name: "R3 QA", zones: [left, right, existing], virtualPlates: [source, target])
    let model = SettingsModel(config: SlotterConfig(workspaces: [workspace], programs: [Program(name: "Editor", path: "/usr/bin/true")]))
    #expect(model.saveDesktopSetup(source.id, name: "Coding") == nil)
    #expect(model.saveDesktopSetup(source.id, name: "coding") != nil)
    let program = try #require(model.programs.first)
    #expect(model.renameProgram(program.id, to: "Renamed Editor") == nil)
    let setup = try #require(model.desktopSetups.first)
    model.loadDesktopSetup(setup, onto: target.id)
    let copied = try #require(model.selectedWorkspace).zones.filter { $0.plateID == target.id }
    #expect(copied.count == 2)
    #expect(copied[0].w == 40 && copied[0].program == "Renamed Editor")
    #expect(copied.allSatisfy { $0.monitor == monitor && $0.id != left.id && $0.id != right.id })
    #expect(model.selectedWorkspace?.virtualPlates == workspace.virtualPlates)
    model.undoLayout()
    #expect(model.selectedWorkspace?.zones.map(\.id) == workspace.zones.map(\.id))
    #expect(model.selectedWorkspace?.zones.first?.program == "Renamed Editor")
    #expect(model.desktopSetups.count == 1)
    model.redoLayout()
    #expect(model.selectedWorkspace?.zones.count == 4)
    let text = ConfigStore().serializedConfig(model.config)
    let reloaded = ConfigStore.parse(IniDocument(text: text))
    #expect(reloaded.desktopSetups.first?.name == "Coding")
    #expect(reloaded.desktopSetups.first?.zones.map(\.w) == [40, 60])
    #expect(reloaded.desktopSetups.first?.zones.first?.program == "Renamed Editor")
}

@Test @MainActor func setupValidationRejectsEmptyPlatesAndUnserialisableNames() {
    let plate = VirtualPlate(name: "Empty", monitor: MonitorRef(ordinal: 1), desktopID: "a")
    let model = SettingsModel(config: SlotterConfig(workspaces: [Workspace(name: "R3 QA", virtualPlates: [plate])]))
    #expect(model.saveDesktopSetup(plate.id, name: "Empty") != nil)
    #expect(model.desktopSetups.isEmpty)
    model.useVirtualMonitor(plate.id)
    #expect(model.saveDesktopSetup(plate.id, name: "Bad\nname") != nil)
    #expect(model.saveDesktopSetup(plate.id, name: "Saved") == nil)
}

@Test @MainActor func corruptSetupCoordinatesCannotBeReinterpretedByDroppingBadFields() {
    let config = ConfigStore.parse(IniDocument(text: """
    [DesktopSetups]
    Count=4
    Name1=Corrupt
    ZoneCount1=1
    Zone1_1=broken,0,0,100,100
    Name2=Corrupt empty field
    ZoneCount2=1
    Zone2_1=,0,0,100,100
    Name3=Outside display
    ZoneCount3=1
    Zone3_1=-10,0,100,100
    Name4=Valid
    ZoneCount4=1
    Zone4_1=0,0,100,100
    """))
    #expect(config.desktopSetups.map(\.name) == ["Valid"])
}

@Test @MainActor func toleratedSetupEdgeRoundingSurvivesSaveAndRestart() throws {
    let monitor = MonitorRef(ordinal: 1)
    let plate = VirtualPlate(name: "Edge", monitor: monitor, desktopID: "a")
    let zone = Zone(monitor: monitor, x: 66.67, y: 0, w: 33.34, h: 100, plateID: plate.id)
    let model = SettingsModel(config: SlotterConfig(workspaces: [Workspace(name: "R3 QA", zones: [zone], virtualPlates: [plate])]))
    #expect(model.saveDesktopSetup(plate.id, name: "Rounded edge") == nil)
    let reloaded = ConfigStore.parse(IniDocument(text: ConfigStore().serializedConfig(model.config)))
    let saved = try #require(reloaded.desktopSetups.first?.zones.first)
    #expect(abs(saved.x + saved.w - 100) < 0.0001)
    let old = ConfigStore.parse(IniDocument(text: "[DesktopSetups]\nCount=1\nName1=Old rounded edge\nZoneCount1=1\nZone1_1=66.67,0,33.34,100\n"))
    #expect(old.desktopSetups.count == 1)
    #expect(abs((old.desktopSetups.first?.zones.first?.w ?? 0) - 33.33) < 0.0001)
}

@Test @MainActor func undoingSetupLoadOntoAnEmptyPlateRestoresItsSettingsInspector() {
    let plate = VirtualPlate(name: "Empty", monitor: MonitorRef(ordinal: 1), desktopID: "a")
    let model = SettingsModel(config: SlotterConfig(workspaces: [Workspace(name: "R3 QA", virtualPlates: [plate])]))
    model.selectVirtualPlate(plate.id)
    let setup = DesktopSetup(name: "Mode", zones: [Zone(monitor: MonitorRef(ordinal: 1), x: 0, y: 0, w: 100, h: 100)])
    model.loadDesktopSetup(setup, onto: plate.id)
    #expect(model.face == .zone)
    model.undoLayout()
    #expect(model.selectedZone == nil)
    #expect(model.selectedVirtualPlateID == plate.id)
    #expect(model.face == .settings)
    #expect(model.canRedoLayout)
}
