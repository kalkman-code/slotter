import Testing
import CoreGraphics
import Foundation
@testable import SlotterKit

private func display(_ id: CGDirectDisplayID, _ name: String, frame: CGRect, pixels: CGSize, mm: CGSize) -> DisplayInfo {
    DisplayInfo(id: id, uuid: "UUID-\(id)", name: name, frameAX: frame, workAreaAX: frame,
                pointSize: frame.size, pixelSize: pixels, isPrimary: id == 1, duplicateIndex: 0,
                physicalSize: mm)
}

private let lgcx = display(1, "LG CX", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                           pixels: CGSize(width: 3840, height: 2160), mm: CGSize(width: 1063, height: 598))
private let ultrawide = display(2, "Ultrawide", frame: CGRect(x: 1920, y: 90, width: 1720, height: 720),
                                pixels: CGSize(width: 3440, height: 1440), mm: CGSize(width: 797, height: 333))

@Test func monitorsAreDrawnAtTheirPhysicalSize() {
    let desk = DeskPlanner.arrange(DisplaySnapshot(displays: [lgcx, ultrawide], flipY: 1080), references: [])
    #expect(desk.trueScale)
    let big = desk.placements[0], wide = desk.placements[1]
    #expect(abs(big.screenWidth - 41.85) < 0.05)
    #expect(abs(wide.screenWidth / big.screenWidth - 0.75) < 0.01)
    #expect(abs((big.monitor.diagonalInches ?? 0) - 48) < 0.2)
    #expect(wide.x > big.x + big.outerWidth)
    #expect(abs(wide.y - 90 / (1920 / (1063 / 25.4))) < 0.01)
    #expect(desk.deskLine > big.bottom && desk.deskLine > wide.bottom)
}

@Test func noReportedSizeFallsBackToPointProportions() {
    let a = display(1, "A", frame: CGRect(x: 0, y: 0, width: 1600, height: 900), pixels: CGSize(width: 3200, height: 1800), mm: .zero)
    let b = display(2, "B", frame: CGRect(x: 1600, y: 0, width: 800, height: 600), pixels: CGSize(width: 800, height: 600), mm: .zero)
    let desk = DeskPlanner.arrange(DisplaySnapshot(displays: [a, b], flipY: 900), references: [])
    #expect(!desk.trueScale)
    #expect(abs(desk.placements[1].screenWidth / desk.placements[0].screenWidth - 0.5) < 0.001)
    #expect(desk.placements[0].monitor.diagonalInches == nil)
}

@Test func aMonitorNoLongerConnectedIsDrawnFromItsLastKnownSize() {
    let snapshot = DisplaySnapshot(displays: [lgcx], flipY: 1080)
    let gone = MonitorRef(ordinal: 2, uuid: "UUID-GONE", legacyKey: "1720x720")
    let desk = DeskPlanner.arrange(snapshot, references: [MonitorRef(ordinal: 1, uuid: "UUID-1"), gone, gone])
    #expect(desk.placements.count == 2)
    let ghost = desk.placements[1].monitor
    #expect(!ghost.isConnected)
    #expect(ghost.id == DeskPlanner.key(for: gone, in: snapshot))
    #expect(ghost.resolutionLabel == "1720 × 720")
}

@Test func aRememberedMonitorKeepsItsNameAndTrueSizeWhileUnplugged() {
    let snapshot = DisplaySnapshot(displays: [lgcx], flipY: 1080)
    let memory = RememberedMonitor(name: "Ultrawide", pixelSize: ultrawide.pixelSize, pointSize: ultrawide.pointSize,
                                   physicalSize: ultrawide.physicalSize, top: 90)
    let ref = MonitorRef(ordinal: 2, uuid: "UUID-2", legacyKey: "1720x720")
    let desk = DeskPlanner.arrange(snapshot, references: [ref], remembered: ["UUID-2": memory])
    let ghost = desk.placements[1]
    #expect(ghost.monitor.name == "Ultrawide")
    #expect(!ghost.monitor.isConnected)
    #expect(abs(ghost.screenWidth - 797 / 25.4) < 0.01)
    #expect(ghost.y > 0)
}
