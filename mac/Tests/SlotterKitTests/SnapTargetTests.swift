import Testing
import Foundation
@testable import SlotterKit

private let display = DisplayInfo(
    id: 1,
    uuid: "TEST-UUID",
    name: "Test Display",
    frameAX: CGRect(x: 0, y: 0, width: 1728, height: 1117),
    workAreaAX: CGRect(x: 0, y: 33, width: 1728, height: 1035),
    pointSize: CGSize(width: 1728, height: 1117),
    pixelSize: CGSize(width: 1728, height: 1117),
    isPrimary: true,
    duplicateIndex: 0)

private let snapshot = DisplaySnapshot(displays: [display], flipY: 1117)

@Test func edgeHitRegionsAnchorToScreenButFramesUseWorkArea() {
    let targets = SnapTargetBuilder.edgeTargets(for: display, startingAt: 0)
    let maximise = targets.first { $0.source == .edge(.maximise) }!

    #expect(maximise.hitRegion.minY == display.frameAX.minY)
    #expect(maximise.frame == display.workAreaAX)

    let thirds = targets.filter {
        $0.source == .edge(.leftThird) || $0.source == .edge(.centreThird) || $0.source == .edge(.rightThird)
    }
    #expect(thirds.count == 3)
    for third in thirds {
        #expect(third.hitRegion.maxY == display.frameAX.maxY)
        #expect(third.frame.minY == display.workAreaAX.minY)
    }
}

@Test func edgeBandsWinInsideTheBandAndZonesWinEverywhereElse() {
    let workspace = Workspace(name: "Full", zones: [
        Zone(monitor: MonitorRef(ordinal: 1, uuid: "TEST-UUID"), x: 0, y: 0, w: 100, h: 100),
    ])
    let built = SnapTargetBuilder.build(workspace: workspace, snapshot: snapshot)

    let insideBand = CGPoint(x: 2, y: 500)
    let hitBand = SnapTargetBuilder.hit(at: insideBand, zones: built.zones, edges: built.edges)
    #expect(hitBand?.source == .edge(.leftHalf))

    let middle = CGPoint(x: 864, y: 500)
    let hitZone = SnapTargetBuilder.hit(at: middle, zones: built.zones, edges: built.edges)
    #expect(hitZone?.source == .zone(index: 0))
}

@Test func edgeTargetsCoincidingWithAZoneAreDropped() {
    let reference = MonitorRef(ordinal: 1, uuid: "TEST-UUID")
    let workspace = Workspace(name: "Halves", zones: [
        Zone(monitor: reference, x: 0, y: 0, w: 50, h: 100),
        Zone(monitor: reference, x: 50, y: 0, w: 50, h: 100),
    ])
    let built = SnapTargetBuilder.build(workspace: workspace, snapshot: snapshot)

    #expect(!built.edges.contains { $0.source == .edge(.leftHalf) })
    #expect(!built.edges.contains { $0.source == .edge(.rightHalf) })
    #expect(built.edges.contains { $0.source == .edge(.maximise) })
}

@Test func dragTargetsUseTheWorkspaceBoundToEachDisplay() {
    let second = DisplayInfo(id: 2, uuid: "SECOND-UUID", name: "Second",
                             frameAX: CGRect(x: 1728, y: 0, width: 1728, height: 1117),
                             workAreaAX: CGRect(x: 1728, y: 33, width: 1728, height: 1035),
                             pointSize: CGSize(width: 1728, height: 1117),
                             pixelSize: CGSize(width: 1728, height: 1117), isPrimary: false, duplicateIndex: 0)
    let both = DisplaySnapshot(displays: [display, second], flipY: 1117)
    let firstWorkspace = Workspace(name: "Writing", zones: [
        Zone(monitor: MonitorRef(ordinal: 1, uuid: display.uuid), x: 0, y: 0, w: 100, h: 100,
             program: "Writer")])
    let secondWorkspace = Workspace(name: "Coding", zones: [
        Zone(monitor: MonitorRef(ordinal: 2, uuid: second.uuid), x: 0, y: 0, w: 100, h: 100,
             program: "Editor")])

    let targets = SnapTargetBuilder.build(workspacesByDisplay: [
        display.uuid: firstWorkspace,
        second.uuid: secondWorkspace,
    ], fallback: nil, snapshot: both)

    #expect(targets.zones.count == 2)
    #expect(targets.zones.map(\.caption) == ["Zone 1 · Writer", "Zone 1 · Editor"])
    #expect(targets.zones.map(\.display) == [display.id, second.id])
}

@Test func overlappingZonesResolveToTheLastDefined() {
    let reference = MonitorRef(ordinal: 1, uuid: "TEST-UUID")
    let workspace = Workspace(name: "Overlap", zones: [
        Zone(monitor: reference, x: 20, y: 20, w: 60, h: 60),
        Zone(monitor: reference, x: 30, y: 30, w: 40, h: 40),
    ])
    let built = SnapTargetBuilder.build(workspace: workspace, snapshot: snapshot)
    let hit = SnapTargetBuilder.hit(at: CGPoint(x: 864, y: 560), zones: built.zones, edges: built.edges)
    #expect(hit?.source == .zone(index: 1))
}

@Test func zoneBoundsArePercentagesOfTheWorkArea() {
    let zone = Zone(monitor: MonitorRef(ordinal: 1, uuid: "TEST-UUID"), x: 50, y: 0, w: 50, h: 100)
    let bounds = ZoneGeometry.bounds(for: zone, in: snapshot)
    #expect(bounds == CGRect(x: 864, y: 33, width: 864, height: 1035))
}

@Test func splittingAZoneKeepsTheProgramOnTheFirstHalfOnly() {
    let zone = Zone(monitor: MonitorRef(ordinal: 1), x: 0, y: 0, w: 100, h: 100, program: "Safari")
    let vertical = ZoneOps.splitVertical(zone)
    #expect(vertical.count == 2)
    #expect(vertical[0].program == "Safari")
    #expect(vertical[1].program == nil)
    #expect(vertical[0].w == 50)
    #expect(vertical[1].x == 50)

    let horizontal = ZoneOps.splitHorizontal(zone)
    #expect(horizontal[0].program == "Safari")
    #expect(horizontal[1].program == nil)
    #expect(horizontal[1].y == 50)
}

@Test func argumentTokeniserHonoursQuotes() {
    #expect(AppLauncher.tokenise("--new-window youtube.com") == ["--new-window", "youtube.com"])
    #expect(AppLauncher.tokenise("-p \"Claude Hub\" -w -1") == ["-p", "Claude Hub", "-w", "-1"])
    #expect(AppLauncher.tokenise("") == [])
}

@Test func shortcutOverridesReplaceAndDisableDefaults() {
    let table = MagnetLayouts.table(overrides: ["leftHalf": "⌃⌥⇧←", "centre": "off"])
    #expect(table[.leftHalf]?.display == "⌃⌥⇧←")
    #expect(table[.centre] == nil)
    #expect(table[.rightHalf] == MagnetLayouts.defaults[.rightHalf])
}

@Test func displayResolutionFallsBackThroughUUIDThenKeyThenOrdinal() {
    #expect(DisplayRegistry.resolve(MonitorRef(ordinal: 9, uuid: "TEST-UUID"), in: snapshot)?.id == 1)
    #expect(DisplayRegistry.resolve(MonitorRef(ordinal: 9, uuid: "MISSING", legacyKey: "1728x1117"),
                                    in: snapshot)?.id == 1)
    #expect(DisplayRegistry.resolve(MonitorRef(ordinal: 1, uuid: "MISSING", legacyKey: "3840x2160"),
                                    in: snapshot)?.id == 1)
    #expect(DisplayRegistry.resolve(MonitorRef(ordinal: 4, uuid: "MISSING", legacyKey: "3840x2160"),
                                    in: snapshot) == nil)
}
