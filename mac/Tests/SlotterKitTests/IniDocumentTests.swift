import Testing
import Foundation
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
    #expect(Validate.workspaceName("coding", in: workspaces) != nil)
    #expect(Validate.workspaceName("a,b", in: workspaces) != nil)
    #expect(Validate.workspaceName("Writing", in: workspaces) == nil)
}
