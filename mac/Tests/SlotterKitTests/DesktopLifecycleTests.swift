import Foundation
import Testing
@testable import SlotterKit
@testable import SlotterUI

private func desktops(_ ids: [String], available: Bool = true) -> SpaceSnapshot {
    SpaceSnapshot(available: available, displays: [ManagedDisplaySpaces(
        displayUUID: "screen", displayName: "Screen", spaces: ids.enumerated().map {
            ManagedSpace(uuid: $0.element, id: UInt64($0.offset + 1), type: 0,
                         ordinal: $0.offset + 1, label: "Desktop \($0.offset + 1)")
        }, currentSpaceUUID: ids.first)])
}

@Test @MainActor func typedDefaultLookingNamesAndClosedDesktopLabelsRoundTrip() throws {
    let monitor = MonitorRef(ordinal: 1, uuid: "screen")
    let plate = VirtualPlate(name: "Desktop 8", monitor: monitor, desktopID: "a")
    let model = SettingsModel(config: SlotterConfig(workspaces: [Workspace(name: "R3 QA", virtualPlates: [plate])]))
    model.renameVirtualPlate(plate.id, to: "Desktop 8")
    #expect(model.workspaces[0].virtualPlates[0].followsDesktopName == false)
    var workspace = model.workspaces[0]
    workspace.reconcileDesktops(desktops(["a"]))
    #expect(workspace.virtualPlates[0].name == "Desktop 8")
    workspace.reconcileDesktops(desktops(["new"]))
    let text = ConfigStore().serializedConfig(SlotterConfig(workspaces: [workspace]))
    let loaded = ConfigStore.parse(IniDocument(text: text))
    #expect(loaded.workspaces == [workspace])
}

@Test func closedDesktopsAreBenchedWhileSurvivorsKeepTheirZonesAndFollowTheirIdentity() {
    let monitor = MonitorRef(ordinal: 1, uuid: "screen")
    let plates = ["a", "b", "c", "d"].enumerated().map {
        VirtualPlate(name: "Desktop \($0.offset + 1)", monitor: monitor, desktopID: $0.element)
    }
    let zones = plates.map { Zone(monitor: monitor, x: 0, y: 0, w: 100, h: 100, program: "Editor", plateID: $0.id) }
    var workspace = Workspace(name: "Test", zones: zones, virtualPlates: plates)
    let changed = workspace.reconcileDesktops(desktops(["d", "a"]))
    #expect(changed)
    #expect(workspace.virtualPlates[0].name == "Desktop 2")
    #expect(workspace.virtualPlates[3].name == "Desktop 1")
    #expect(workspace.virtualPlates[1].desktopID == nil)
    #expect(workspace.virtualPlates[2].desktopID == nil)
    #expect(workspace.virtualPlates[1].closedDesktopLabel == "Desktop 2")
    #expect(workspace.zones == zones)
    let reopened = workspace.reconcileDesktops(desktops(["d", "a", "new"]))
    #expect(!reopened)
    #expect(workspace.virtualPlates[1].desktopID == nil)
}

@Test func customDesktopNamesAndDisconnectedDisplaysArePreserved() {
    var typed = VirtualPlate(name: "Desktop 8", monitor: MonitorRef(ordinal: 1, uuid: "screen"), desktopID: "a")
    typed.followsDesktopName = false
    let offline = VirtualPlate(name: "Desktop 3", monitor: MonitorRef(ordinal: 2, uuid: "offline"), desktopID: "gone")
    var workspace = Workspace(name: "Test", virtualPlates: [typed, offline])
    let renamed = workspace.reconcileDesktops(desktops(["a"]))
    #expect(!renamed)
    #expect(workspace.virtualPlates == [typed, offline])
    let unavailable = workspace.reconcileDesktops(desktops([], available: false))
    #expect(!unavailable)
}
