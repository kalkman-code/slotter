import Foundation
import Testing
@testable import SlotterKit

@Test func desktopSwitchingHonoursEnabledCustomShortcutsAndRejectsMissingOrInvalidOnes() {
    let entry: [String: Any] = ["enabled": true, "value": ["type": "standard", "parameters": [65535, 42, 786432]]]
    let configured = DesktopSwitcher.shortcut(ordinal: 2, preferences: ["119": entry])
    #expect(configured == DesktopSwitcher.Shortcut(keyCode: 42, flags: 786432))
    #expect(DesktopSwitcher.shortcut(ordinal: 1, preferences: ["119": entry]) == nil)
    #expect(DesktopSwitcher.shortcut(ordinal: 0, preferences: [:]) == nil)
    #expect(DesktopSwitcher.shortcut(ordinal: 2, preferences: ["119": ["enabled": false]]) == nil)
    #expect(DesktopSwitcher.shortcut(ordinal: 2, preferences: ["119": ["enabled": true, "value": ["type": "standard", "parameters": [65535, 65535, 0]]]]) == nil)
}
