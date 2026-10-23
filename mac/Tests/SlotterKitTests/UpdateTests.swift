import Foundation
import Sparkle
import Testing
@testable import SlotterUI

@Test func updateOrderingUsesBuildNumbersRatherThanDisplayVersions() {
    let comparator = SUStandardVersionComparator.default
    #expect(comparator.compareVersion("99", toVersion: "100") == .orderedAscending)
    #expect(comparator.compareVersion("160", toVersion: "160") == .orderedSame)
    #expect(comparator.compareVersion("161", toVersion: "160") == .orderedDescending)
}

@Test func macSelectionSkipsWindowsAndUsesHighestBuild() throws {
    func item(_ build: String, _ short: String, _ os: String? = nil) throws -> SUAppcastItem {
        var enclosure = ["url": "https://example.com/Slotter.dmg", "length": "10", "type": "application/octet-stream"]
        if let os { enclosure["sparkle:os"] = os }
        return try #require(SUAppcastItem(dictionary: ["sparkle:version": build,
            "sparkle:shortVersionString": short, "enclosure": enclosure]))
    }
    let old = try item("160", "1.0.0-alpha.2")
    let newer = try item("161", "1.0.0-alpha.99", "macos")
    let windows = try item("9999", "9.0.0", "windows")
    #expect(!windows.isMacOsUpdate)
    #expect(UpdateSelection.bestMacUpdate(in: [windows, newer, old])?.versionString == "161")
    #expect(UpdateSelection.bestMacUpdate(in: [old, newer, windows])?.displayVersionString == "1.0.0-alpha.99")
    #expect(UpdateSelection.bestMacUpdate(in: [windows]) == nil)
}

@Test @MainActor func stagedFeedOverrideIsExplicitAndLoopbackOnlyForHTTP() {
    let info: [String: Any] = ["SUFeedURL": "https://kalkmancode.co.uk/slotter/appcast.xml"]
    #expect(UpdateController.feedURL(environment: [:], info: info)?.scheme == "https")
    #expect(UpdateController.feedURL(environment: ["SLOTTER_FEED_URL": "http://127.0.0.1:8765/appcast.xml"], info: info)?.port == 8765)
    #expect(UpdateController.feedURL(environment: ["SLOTTER_FEED_URL": "http://localhost:8765/appcast.xml"], info: info) != nil)
    #expect(UpdateController.feedURL(environment: ["SLOTTER_FEED_URL": "http://example.com/appcast.xml"], info: info) == nil)
    #expect(UpdateController.feedURL(environment: ["SLOTTER_FEED_URL": "file:///tmp/appcast.xml"], info: info) == nil)
}
