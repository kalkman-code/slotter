import Testing
import ApplicationServices
@testable import SlotterKit

private func activeDesktop(_ id: UInt64, type: Int = 0) -> SpaceSnapshot {
    let space = ManagedSpace(uuid: "space-\(id)", id: id, type: type, ordinal: 1, label: "Desktop 1")
    return SpaceSnapshot(available: true, displays: [ManagedDisplaySpaces(displayUUID: "screen", displayName: "Screen", spaces: [space], currentSpaceUUID: space.uuid)])
}

@Test func changedDesktopValidationStopsPlacementBeforeAnyWindowInspection() {
    let invalidWindow = AXElement(AXUIElementCreateApplication(0))
    let result = WindowPlacer.place(invalidWindow, into: CGRect(x: 0, y: 0, width: 100, height: 100), validation: { false })
    #expect(result.failure == .desktopChanged)
    #expect(result.applied == nil)
}

@Test func windowDesktopMembershipRejectsUnknownOffDesktopAndChangedContexts() {
    let expected = activeDesktop(1)
    #expect(SpaceRegistry.membershipMatches([1], expected: expected, current: expected))
    #expect(SpaceRegistry.membershipMatches([1, 2], expected: expected, current: expected))
    #expect(!SpaceRegistry.membershipMatches([2], expected: expected, current: expected))
    #expect(!SpaceRegistry.membershipMatches(nil, expected: expected, current: expected))
    #expect(!SpaceRegistry.membershipMatches([], expected: expected, current: expected))
    #expect(!SpaceRegistry.membershipMatches([1], expected: expected, current: activeDesktop(2)))
    #expect(!SpaceRegistry.membershipMatches([1], expected: expected, current: SpaceSnapshot(available: false)))
    #expect(!SpaceRegistry.membershipMatches([1], expected: activeDesktop(1, type: 4), current: activeDesktop(1, type: 4)))
}
