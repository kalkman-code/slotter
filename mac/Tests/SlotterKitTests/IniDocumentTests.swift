import Testing
import Foundation
import Carbon.HIToolbox
@testable import SlotterKit

private let sample = """
; Slotter config — hand-edited
[Profiles]
List=Coding,Writing

[Panel]
LastProfile=Coding

[Settings]
StartAtLogin=1
SomeFutureKey=keepme

[Coding]
Zone1=1,0,0,50,100
MonUUID1=ABC-123
Prog1=Safari
Zone2=1,50,0,50,100
MonUUID2=ABC-123

[Programs]
Count=1
Name1=Safari
Exe1=/Applications/Safari.app
Args1=
"""

@Test func readsValuesCaseInsensitively() {
    let document = IniDocument(text: sample)
    #expect(document.string("profiles", "list") == "Coding,Writing")
    #expect(document.string("Coding", "ZONE1") == "1,0,0,50,100")
    #expect(document.bool("Settings", "StartAtLogin"))
}

@Test @MainActor func corruptCountsCannotTurnASmallConfigIntoBillionsOfLookups() {
    let config = ConfigStore.parse(IniDocument(text: """
    [Profiles]
    List=R3 QA
    [R3 QA]
    VirtualPlateCount=2147483647
    VirtualPlate1ID=AC8CDB8A-E317-4AC2-859B-B18FF7885CA1
    VirtualPlate1Monitor=1|screen||0
    Zone1=1,nan,inf,-20,200
    [Programs]
    Count=2147483647
    Name1=Editor
    Exe1=/usr/bin/true
    """))
    #expect(config.workspaces.count == 1)
    #expect(config.workspaces.first?.virtualPlates.count == 1)
    #expect(config.programs.map(\.name) == ["Editor"])
    #expect(config.workspaces.flatMap(\.zones).allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.w.isFinite && $0.h.isFinite })
}

@Test func roundTripsUnchangedTextByteForByte() {
    let document = IniDocument(text: sample)
    #expect(document.serialized() == sample + "\n")
}

@Test func preservesCommentsBlankLinesAndUnknownKeys() {
    var document = IniDocument(text: sample)
    document.replaceSection("Coding", removingKeysMatching: { key in
        key.lowercased().hasPrefix("zone") || key.lowercased().hasPrefix("monuuid") || key.lowercased().hasPrefix("prog")
    }, with: [("Zone1", "1,0,0,100,100"), ("MonUUID1", "ABC-123")])

    let output = document.serialized()
    #expect(output.hasPrefix("; Slotter config — hand-edited"))
    #expect(output.contains("SomeFutureKey=keepme"))
    #expect(output.contains("Zone1=1,0,0,100,100"))
    #expect(!output.contains("Zone2="))
    #expect(output.contains("\n\n[Panel]"))
}

@Test func setAddsMissingSectionAndKey() {
    var document = IniDocument(text: sample)
    document.set("Shortcuts", "leftHalf", "⌃⌥←")
    #expect(document.string("Shortcuts", "leftHalf") == "⌃⌥←")
    #expect(document.serialized().contains("[Shortcuts]"))
}

@Test func removeSectionDropsHeaderAndBody() {
    var document = IniDocument(text: sample)
    document.removeSection("Coding")
    #expect(!document.hasSection("Coding"))
    #expect(!document.serialized().contains("Zone1="))
    #expect(document.serialized().contains("[Programs]"))
}

@Test func zoneClampingKeepsPercentagesInBounds() {
    let zone = Zone(monitor: MonitorRef(ordinal: 1), x: 80, y: 95, w: 60, h: 40).clamped()
    #expect(zone.w == 20)
    #expect(zone.h == 5)
}

@Test func thirdsTileExactlyWithoutGaps() {
    let work = CGRect(x: 0, y: 33, width: 1728, height: 1035)
    let left = MagnetLayouts.frame(for: .leftThird, work: work, current: .zero)!
    let centre = MagnetLayouts.frame(for: .centreThird, work: work, current: .zero)!
    let right = MagnetLayouts.frame(for: .rightThird, work: work, current: .zero)!
    #expect(left.maxX == centre.minX)
    #expect(centre.maxX == right.minX)
    #expect(right.maxX == work.maxX)
}

@Test func halvesTileExactlyWithoutGaps() {
    let work = CGRect(x: 0, y: 33, width: 1727, height: 1035)
    let left = MagnetLayouts.frame(for: .leftHalf, work: work, current: .zero)!
    let right = MagnetLayouts.frame(for: .rightHalf, work: work, current: .zero)!
    #expect(left.maxX == right.minX)
    #expect(right.maxX == work.maxX)
}

@Test func axCocoaConversionIsAnInvolution() {
    let rect = CGRect(x: 10, y: 40, width: 300, height: 200)
    let flipY: CGFloat = 1117
    #expect(Geo.ax(fromCocoa: Geo.cocoa(fromAX: rect, flipY: flipY), flipY: flipY) == rect)
}

@Test func workspaceNameValidationRejectsReservedAndDuplicates() {
    let workspaces = [Workspace(name: "Coding")]
    #expect(Validate.workspaceName("Programs", in: workspaces) != nil)
    #expect(Validate.workspaceName("Shortcuts", in: workspaces) != nil)
    #expect(Validate.workspaceName("SpaceBindings", in: workspaces) != nil)
    #expect(Validate.workspaceName("coding", in: workspaces) != nil)
    #expect(Validate.workspaceName("a,b", in: workspaces) != nil)
    #expect(Validate.workspaceName("Writing", in: workspaces) == nil)
}

@Test @MainActor func shortcutConfigDropsLegacyBindingsAndKeepsExplicitUnboundValues() {
    let workspaceID = UUID()
    let workspace = Workspace(name: "Coding", id: workspaceID)
    let config = SlotterConfig(workspaces: [workspace], shortcuts: [
        "leftHalf": "⌃⌥A",
        "rightHalf": "none",
    ])

    let text = ConfigStore().serializedConfig(config, preserving: "[SpaceBindings]\nFollowDesktop=1\nBinding1=screen-a|space-a|\(workspaceID.uuidString)\n")
    let loaded = ConfigStore.parse(IniDocument(text: text))

    #expect(loaded.shortcuts["leftHalf"] == "⌃⌥A")
    #expect(loaded.shortcuts["rightHalf"] == "none")
    #expect(MagnetLayouts.table(overrides: loaded.shortcuts)[.rightHalf] == nil)
    #expect(loaded.workspaces.first?.id == workspaceID)
    #expect(!text.contains("[SpaceBindings]"))
}

@Test @MainActor func virtualPlatesAndZonePlateIDsRoundTripIncludingBenchedPlate() {
    let monitor = MonitorRef(ordinal: 2, uuid: "screen-a", legacyKey: "1728x1117", duplicateIndex: 1)
    let pinned = VirtualPlate(name: "Writing", monitor: monitor, desktopID: "space-a")
    let benched = VirtualPlate(name: "Research", monitor: monitor, desktopID: nil)
    let workspace = Workspace(name: "Coding", zones: [
        Zone(monitor: monitor, x: 0, y: 0, w: 50, h: 100, plateID: pinned.id),
    ], virtualPlates: [pinned, benched])

    let text = ConfigStore().serializedConfig(SlotterConfig(workspaces: [workspace]))
    let loaded = ConfigStore.parse(IniDocument(text: text)).workspaces[0]

    #expect(loaded.virtualPlates == [pinned, benched])
    #expect(loaded.zones[0].plateID == pinned.id)
}

@Test func keyComboNamesRoundTripCommonKeys() {
    let names = ["A", "Z", "0", "9", "F1", "F20", "←", "→", "↑", "↓", "↩", "⌫", "⌦",
                 "Space", "Tab", "`", "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/"]
    for name in names {
        let combo = KeyCombo.parse("⌃⌥\(name)")
        #expect(combo != nil)
        #expect(combo.map { "⌃⌥\(KeyCombo.name(for: $0.keyCode))" } == "⌃⌥\(name)")
    }
    #expect(KeyCombo.parse("A") == nil)
}

@Test func keyComboNamesRoundTripUnlistedKeyCodes() {
    let keypadOne = KeyCombo(keyCode: 83, modifiers: UInt32(controlKey))
    #expect(keypadOne.display == "⌃key 83")
    #expect(KeyCombo.parse(keypadOne.display) == keypadOne)
}

@Test @MainActor func savedNumericShortcutReloadsWithItsOriginalKeyCode() {
    let workspace = Workspace(name: "Coding")
    let config = SlotterConfig(workspaces: [workspace], shortcuts: ["leftHalf": "⌃key 83"])

    let saved = ConfigStore().serializedConfig(config)
    let loaded = ConfigStore.parse(IniDocument(text: saved))

    #expect(MagnetLayouts.table(overrides: loaded.shortcuts)[.leftHalf] == KeyCombo(keyCode: 83,
                                                                                   modifiers: UInt32(controlKey)))
}

@Test func parsesManagedSpaceIDsFromCGSSpaceDictionaries() {
    let item: [String: Any] = [
        "Current Space": ["ManagedSpaceID": 10, "id64": 20],
        "Spaces": [
            ["uuid": "space-a", "ManagedSpaceID": 10, "type": 0],
            ["uuid": "space-b", "id64": 20, "type": 0],
        ],
    ]

    let display = SpaceRegistry.parseDisplaySpaces(item, displayUUID: "screen-a", displayName: "LG CX",
                                                   activeSpaceID: 10)

    #expect(display?.spaces.map(\.id) == [10, 20])
    #expect(display?.currentSpaceUUID == "space-a")
}

@Test func readsLegacyID64ForCurrentSpaceWhenManagedSpaceIDIsAbsent() {
    let item: [String: Any] = [
        "Current Space": ["id64": 20],
        "Spaces": [
            ["uuid": "space-a", "ManagedSpaceID": 10, "type": 0],
            ["uuid": "space-b", "id64": 20, "type": 0],
        ],
    ]

    let display = SpaceRegistry.parseDisplaySpaces(item, displayUUID: "screen-a", displayName: "LG CX",
                                                   activeSpaceID: 10)

    #expect(display?.currentSpaceUUID == "space-b")
}

@Test func rejectsCGSSpaceDictionariesWithoutUsableSpaces() {
    let item: [String: Any] = [
        "Current Space": ["ManagedSpaceID": 20],
        "Spaces": [["uuid": "missing-id", "type": 0]],
    ]

    #expect(SpaceRegistry.parseDisplaySpaces(item, displayUUID: "screen-a", displayName: "LG CX",
                                             activeSpaceID: 20) == nil)
}

@Test func shortcutConflictDetectionExcludesTheEditedAction() {
    let combo = KeyCombo.parse("⌃⌥A")!
    let overrides = ["leftHalf": "⌃⌥A", "rightHalf": "⌃⌥A"]
    #expect(ShortcutRules.conflict(for: combo, excluding: .rightHalf, overrides: overrides) == .leftHalf)
    #expect(ShortcutRules.conflict(for: combo, excluding: .leftHalf, overrides: overrides) == .rightHalf)
}

private struct FakeSpaceRegistry: SpaceRegistryProviding {
    let value: SpaceSnapshot
    func snapshot() -> SpaceSnapshot { value }
}

@Test func launchPlanUsesEachDisplaysCurrentPlateWithoutLaunchingBenchedOrOtherDesktops() {
    let a = MonitorRef(ordinal: 1, uuid: "screen-a")
    let b = MonitorRef(ordinal: 2, uuid: "screen-b")
    let active = VirtualPlate(name: "Current", monitor: a, desktopID: "space-a")
    let other = VirtualPlate(name: "Other", monitor: a, desktopID: "space-other")
    let bench = VirtualPlate(name: "Saved", monitor: b, desktopID: nil)
    let physicalA = Zone(monitor: a, x: 0, y: 0, w: 100, h: 100, program: "Wrong physical")
    let physicalB = Zone(monitor: b, x: 0, y: 0, w: 100, h: 100, program: "Physical B")
    let current = Zone(monitor: a, x: 0, y: 0, w: 50, h: 100, program: "Writer", plateID: active.id)
    let inactive = Zone(monitor: a, x: 50, y: 0, w: 50, h: 100, program: "Other", plateID: other.id)
    let benched = Zone(monitor: b, x: 0, y: 0, w: 100, h: 100, program: "Saved", plateID: bench.id)
    let workspace = Workspace(name: "Desk", zones: [physicalA, physicalB, current, inactive, benched],
                              virtualPlates: [active, other, bench])
    let space = ManagedSpace(uuid: "space-a", id: 1, type: 0, ordinal: 1, label: "Desktop 1")
    let registry = FakeSpaceRegistry(value: SpaceSnapshot(available: true, displays: [
        ManagedDisplaySpaces(displayUUID: "screen-a", displayName: "A", spaces: [space], currentSpaceUUID: space.uuid),
        ManagedDisplaySpaces(displayUUID: "screen-b", displayName: "B", spaces: [], currentSpaceUUID: nil)
    ]))
    let plan = VirtualPlateResolver(registry: registry).workspaceForLaunch(workspace)
    #expect(plan.zones == [physicalB, current])
    #expect(plan.id == workspace.id)
    #expect(workspace.zones.count == 5)
    let unavailable = FakeSpaceRegistry(value: SpaceSnapshot(available: false))
    #expect(VirtualPlateResolver(registry: unavailable).workspaceForLaunch(workspace).zones == [physicalA, physicalB])
}

@Test func virtualPlateResolutionFallsBackToManualWorkspacePerDisplay() {
    let monitor = MonitorRef(ordinal: 1, uuid: "screen-a")
    let physical = Zone(monitor: monitor, x: 0, y: 0, w: 50, h: 100)
    let virtualPlate = VirtualPlate(name: "Saved", monitor: monitor, desktopID: "space-old")
    let virtual = Zone(monitor: monitor, x: 50, y: 0, w: 50, h: 100, plateID: virtualPlate.id)
    let first = Workspace(name: "Manual", zones: [physical, virtual], virtualPlates: [virtualPlate])
    let displayA = ManagedDisplaySpaces(displayUUID: "screen-a", displayName: "LG CX",
                                       spaces: [ManagedSpace(uuid: "space-a", id: 10, type: 0,
                                                             ordinal: 2, label: "Desktop 2")],
                                       currentSpaceUUID: "space-a")
    let displayB = ManagedDisplaySpaces(displayUUID: "screen-b", displayName: "Studio Display",
                                       spaces: [ManagedSpace(uuid: "space-b", id: 20, type: 0,
                                                             ordinal: 1, label: "Desktop 1")],
                                       currentSpaceUUID: "space-b")
    let registry = FakeSpaceRegistry(value: SpaceSnapshot(available: true, displays: [displayA, displayB]))
    let result = VirtualPlateResolver(registry: registry).resolve(manualWorkspace: first, workspaces: [first])

    #expect(result.snapshot.available)
    #expect(result.workspacesByDisplay["screen-a"]?.id == first.id)
    #expect(result.workspacesByDisplay["screen-b"]?.id == first.id)
    #expect(result.workspacesByDisplay["screen-a"]?.zones == [physical])
}

@Test func independentDisplaysKeepTheirOwnLaunchPlateWhenOneDesktopChanges() {
    let a = MonitorRef(ordinal: 1, uuid: "screen-a")
    let b = MonitorRef(ordinal: 2, uuid: "screen-b")
    let a1 = ManagedSpace(uuid: "a1", id: 1, type: 0, ordinal: 1, label: "Desktop 1")
    let a2 = ManagedSpace(uuid: "a2", id: 2, type: 0, ordinal: 2, label: "Desktop 2")
    let b1 = ManagedSpace(uuid: "b1", id: 3, type: 0, ordinal: 1, label: "Desktop 1")
    let b2 = ManagedSpace(uuid: "b2", id: 4, type: 0, ordinal: 2, label: "Desktop 2")
    let plates = [(a, a1), (a, a2), (b, b1), (b, b2)].map {
        VirtualPlate(name: $0.1.uuid, monitor: $0.0, desktopID: $0.1.uuid)
    }
    let zones = plates.map { Zone(monitor: $0.monitor, x: 0, y: 0, w: 100, h: 100, program: $0.name, plateID: $0.id) }
    let workspace = Workspace(name: "Independent", zones: zones, virtualPlates: plates)
    func plan(_ currentA: String) -> Workspace {
        let registry = FakeSpaceRegistry(value: SpaceSnapshot(available: true, displays: [
            ManagedDisplaySpaces(displayUUID: "screen-a", displayName: "A", spaces: [a1, a2], currentSpaceUUID: currentA),
            ManagedDisplaySpaces(displayUUID: "screen-b", displayName: "B", spaces: [b1, b2], currentSpaceUUID: "b1")
        ]))
        return VirtualPlateResolver(registry: registry).workspaceForLaunch(workspace)
    }
    #expect(plan("a1").zones == [zones[0], zones[2]])
    #expect(plan("a2").zones == [zones[1], zones[2]])
    #expect(workspace.zones == zones)
}

@Test func virtualPlateResolutionSelectsPinnedWorkspaceOnMatchingDesktop() {
    let manual = Workspace(name: "Manual")
    let displayA = ManagedDisplaySpaces(displayUUID: "screen-a", displayName: "LG CX",
                                       spaces: [ManagedSpace(uuid: "space-a", id: 10, type: 0,
                                                             ordinal: 1, label: "Desktop 1")],
                                       currentSpaceUUID: "space-a")
    let displayB = ManagedDisplaySpaces(displayUUID: "screen-b", displayName: "Studio Display",
                                       spaces: [ManagedSpace(uuid: "space-b", id: 20, type: 0,
                                                             ordinal: 3, label: "Desktop 3")],
                                       currentSpaceUUID: "space-b")
    let registry = FakeSpaceRegistry(value: SpaceSnapshot(available: true, displays: [displayA, displayB]))
    let firstPlate = VirtualPlate(name: "Desktop 1", monitor: MonitorRef(ordinal: 1, uuid: "screen-a"), desktopID: "space-a")
    let first = Workspace(name: "Writing", zones: [Zone(monitor: firstPlate.monitor, x: 0, y: 0, w: 50, h: 100, plateID: firstPlate.id)], virtualPlates: [firstPlate])
    let physical = Zone(monitor: firstPlate.monitor, x: 0, y: 0, w: 100, h: 100)
    var workspaceWithBothLayouts = first
    workspaceWithBothLayouts.zones = [physical] + first.zones
    let second = Workspace(name: "Design")
    let result = VirtualPlateResolver(registry: registry).resolve(manualWorkspace: workspaceWithBothLayouts,
                                                                 workspaces: [manual, workspaceWithBothLayouts, second])

    #expect(result.workspacesByDisplay["screen-a"]?.id == first.id)
    #expect(result.workspacesByDisplay["screen-a"]?.zones == first.zones)
    #expect(result.workspacesByDisplay["screen-b"]?.id == workspaceWithBothLayouts.id)
}

@Test func virtualPlateResolutionOnlyUsesTheActiveWorkspace() {
    let monitor = MonitorRef(ordinal: 1, uuid: "screen-a")
    let manual = Workspace(name: "Active", zones: [Zone(monitor: monitor, x: 0, y: 0, w: 100, h: 100)])
    let otherPlate = VirtualPlate(name: "Other workspace", monitor: monitor, desktopID: "space-a")
    let other = Workspace(name: "Other", zones: [
        Zone(monitor: monitor, x: 0, y: 0, w: 50, h: 100, plateID: otherPlate.id)
    ], virtualPlates: [otherPlate])
    let display = ManagedDisplaySpaces(displayUUID: "screen-a", displayName: "LG CX",
                                       spaces: [ManagedSpace(uuid: "space-a", id: 10, type: 0,
                                                             ordinal: 1, label: "Desktop 1")],
                                       currentSpaceUUID: "space-a")
    let registry = FakeSpaceRegistry(value: SpaceSnapshot(available: true, displays: [display]))
    let result = VirtualPlateResolver(registry: registry).resolve(manualWorkspace: manual, workspaces: [other, manual])

    #expect(result.workspacesByDisplay["screen-a"] == manual)
}

@Test func unavailableSpaceDetectionFallsBackToPhysicalZonesOnly() {
    let monitor = MonitorRef(ordinal: 1, uuid: "screen-a")
    let physical = Zone(monitor: monitor, x: 0, y: 0, w: 100, h: 100)
    let plate = VirtualPlate(name: "Saved", monitor: monitor, desktopID: "space-a")
    let virtual = Zone(monitor: monitor, x: 0, y: 0, w: 50, h: 100, plateID: plate.id)
    let manual = Workspace(name: "Manual", zones: [physical, virtual], virtualPlates: [plate])
    let display = ManagedDisplaySpaces(displayUUID: "screen-a", displayName: "LG CX",
                                       spaces: [ManagedSpace(uuid: "space-a", id: 10, type: 0,
                                                             ordinal: 1, label: "Desktop 1")],
                                       currentSpaceUUID: "space-a")
    let registry = FakeSpaceRegistry(value: SpaceSnapshot(available: false, displays: [display]))
    let result = VirtualPlateResolver(registry: registry).resolve(manualWorkspace: manual, workspaces: [manual])

    #expect(result.workspacesByDisplay["screen-a"]?.zones == [physical])
}

@Test func fullscreenSpaceFallsBackToPhysicalWorkspace() {
    let monitor = MonitorRef(ordinal: 1, uuid: "screen-a")
    let physical = Zone(monitor: monitor, x: 0, y: 0, w: 100, h: 100)
    let plate = VirtualPlate(name: "Saved", monitor: monitor, desktopID: "full")
    let virtual = Zone(monitor: monitor, x: 0, y: 0, w: 50, h: 100, plateID: plate.id)
    let manual = Workspace(name: "Manual", zones: [physical, virtual], virtualPlates: [plate])
    let previous = Workspace(name: "Bound")
    let display = ManagedDisplaySpaces(displayUUID: "screen-a", displayName: "LG CX",
                                      spaces: [ManagedSpace(uuid: "full", id: 45, type: 4,
                                                            ordinal: nil, label: "Fullscreen")],
                                      currentSpaceUUID: "full")
    let registry = FakeSpaceRegistry(value: SpaceSnapshot(available: true, displays: [display]))
    let result = VirtualPlateResolver(registry: registry).resolve(manualWorkspace: manual, workspaces: [previous, manual])
    #expect(result.workspacesByDisplay["screen-a"]?.zones == [physical])
}
