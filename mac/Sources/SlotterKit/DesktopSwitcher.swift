import AppKit
import CoreGraphics
import Foundation

public enum DesktopSwitcher {
    public struct Shortcut: Equatable, Sendable {
        public var keyCode: UInt16
        public var flags: UInt64
    }

    public static func shortcut(ordinal: Int, preferences: [String: Any]) -> Shortcut? {
        guard (1...16).contains(ordinal),
              let entry = preferences[String(117 + ordinal)] as? [String: Any],
              (entry["enabled"] as? NSNumber)?.boolValue == true,
              let value = entry["value"] as? [String: Any],
              value["type"] as? String == "standard",
              let parameters = value["parameters"] as? [NSNumber], parameters.count == 3,
              (0...127).contains(parameters[1].intValue) else { return nil }
        return Shortcut(keyCode: parameters[1].uint16Value, flags: parameters[2].uint64Value)
    }

    public static func show(_ plate: VirtualPlate) -> String? {
        let snapshot = SpaceRegistry.shared.snapshot()
        guard snapshot.available,
              let display = snapshot.displays.first(where: { $0.spaces.contains { $0.uuid == plate.desktopID } }),
              let target = display.spaces.first(where: { $0.uuid == plate.desktopID }), let ordinal = target.ordinal else {
            return "This desktop is no longer available. Choose another desktop for the plate."
        }
        if display.currentSpaceUUID == target.uuid { return nil }
        guard AX.isTrusted else { return "Allow Slotter in Accessibility settings to switch desktops." }
        let preferences = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any] ?? [:]
        guard let shortcut = shortcut(ordinal: ordinal, preferences: preferences) else {
            return "Enable “Switch to Desktop \(ordinal)” in System Settings → Keyboard → Keyboard Shortcuts → Mission Control, then try again. Slotter uses your configured shortcut."
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: false) else {
            return "macOS could not create the desktop shortcut. Try again."
        }
        down.flags = CGEventFlags(rawValue: shortcut.flags)
        up.flags = down.flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return nil
    }
}
