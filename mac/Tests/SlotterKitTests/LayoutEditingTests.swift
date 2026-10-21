import Testing
import Foundation
@testable import SlotterKit

private let monitor = MonitorRef(ordinal: 1)

@Test func customGridTilesFiveColumnsAndTwoRows() throws {
    let preset = try #require(PresetCatalog.grid(columns: 5, rows: 2))
    let zones = ZoneOps.zones(from: preset, monitor: monitor)
    #expect(zones.count == 10)
    #expect(zones[4].x == 80 && zones[4].w == 20)
    #expect(zones[5].y == 50 && zones[5].h == 50)
    #expect(zones.reduce(0) { $0 + $1.w * $1.h } == 10000)
}

@Test func unevenGridSharesExactEdges() throws {
    let preset = try #require(PresetCatalog.grid(columns: 7, rows: 3))
    let zones = ZoneOps.zones(from: preset, monitor: monitor)
    for row in 0..<3 {
        for column in 0..<6 {
            let a = zones[row * 7 + column], b = zones[row * 7 + column + 1]
            #expect(abs(a.x + a.w - b.x) < 0.000001)
        }
        #expect(abs(zones[row * 7 + 6].x + zones[row * 7 + 6].w - 100) < 0.000001)
    }
    #expect(PresetCatalog.grid(columns: 0, rows: 2) == nil)
    #expect(PresetCatalog.grid(columns: 21, rows: 2) == nil)
}

@Test func fillingDeletedMiddleRowsCreatesOneTripleHeightSlot() throws {
    let occupied = [Zone(monitor: monitor, x: 0, y: 0, w: 100, h: 20),
                    Zone(monitor: monitor, x: 0, y: 80, w: 100, h: 20)]
    let gap = try #require(ZoneOps.largestFreeSpace(among: occupied))
    #expect(gap == ZoneFraction(0, 20, 100, 60))
}

@Test func fillingDoesNotOverlapAnLShapedArrangement() throws {
    let occupied = [Zone(monitor: monitor, x: 0, y: 0, w: 30, h: 100),
                    Zone(monitor: monitor, x: 30, y: 0, w: 70, h: 40)]
    let gap = try #require(ZoneOps.largestFreeSpace(among: occupied))
    #expect(gap == ZoneFraction(30, 40, 70, 60))
    #expect(ZoneOps.largestFreeSpace(among: occupied + [Zone(monitor: monitor, x: gap.x, y: gap.y, w: gap.w, h: gap.h)]) == nil)
}

@Test func fillingIsStableWithOverlapsAndPrefersTopLeftTies() throws {
    let occupied = [Zone(monitor: monitor, x: 40, y: 0, w: 20, h: 100),
                    Zone(monitor: monitor, x: 45, y: 20, w: 10, h: 30)]
    #expect(ZoneOps.largestFreeSpace(among: occupied) == ZoneFraction(0, 0, 40, 100))
    #expect(ZoneOps.largestFreeSpace(among: []) == ZoneFraction(0, 0, 100, 100))
    #expect(ZoneOps.largestFreeSpace(among: [Zone(monitor: monitor, x: 0, y: 0, w: 100, h: 100)]) == nil)
}

@Test func gapRoundingNeverExpandsIntoExistingSlots() throws {
    let gap = try #require(ZoneOps.largestFreeSpace(among: [Zone(monitor: monitor, x: 0, y: 0, w: 33.335, h: 100)]))
    #expect(gap.x >= 33.335)
    #expect(gap.x + gap.w <= 100)
}
