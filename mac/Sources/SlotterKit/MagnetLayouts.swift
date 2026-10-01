import Carbon.HIToolbox
import Foundation

public enum SnapAction: String, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centreThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case maximise, centre, restore
    case nextDisplay, previousDisplay

    public var title: String {
        switch self {
        case .leftHalf: return "Left half"
        case .rightHalf: return "Right half"
        case .topHalf: return "Top half"
        case .bottomHalf: return "Bottom half"
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        case .leftThird: return "Left third"
        case .centreThird: return "Centre third"
        case .rightThird: return "Right third"
        case .leftTwoThirds: return "Left two thirds"
        case .rightTwoThirds: return "Right two thirds"
        case .maximise: return "Maximise"
        case .centre: return "Centre"
        case .restore: return "Restore"
        case .nextDisplay: return "Next display"
        case .previousDisplay: return "Previous display"
        }
    }
}

public struct KeyCombo: Sendable, Hashable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let controlOption = UInt32(controlKey | optionKey)
    public static let controlOptionCommand = UInt32(controlKey | optionKey | cmdKey)

    public var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + KeyCombo.name(for: keyCode)
    }

    public static func name(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Return: return "↩"
        case kVK_Delete: return "⌫"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_C: return "C"
        default: return "key \(keyCode)"
        }
    }

    public static func parse(_ text: String) -> KeyCombo? {
        var modifiers: UInt32 = 0
        var remainder = ""
        for character in text {
            switch character {
            case "⌃": modifiers |= UInt32(controlKey)
            case "⌥": modifiers |= UInt32(optionKey)
            case "⇧": modifiers |= UInt32(shiftKey)
            case "⌘": modifiers |= UInt32(cmdKey)
            default: remainder.append(character)
            }
        }
        let key = remainder.trimmingCharacters(in: .whitespaces).uppercased()
        guard modifiers != 0, let code = keyCode(named: key) else { return nil }
        return KeyCombo(keyCode: code, modifiers: modifiers)
    }

    private static func keyCode(named key: String) -> UInt32? {
        let table: [String: Int] = [
            "←": kVK_LeftArrow, "→": kVK_RightArrow, "↑": kVK_UpArrow, "↓": kVK_DownArrow,
            "LEFT": kVK_LeftArrow, "RIGHT": kVK_RightArrow, "UP": kVK_UpArrow, "DOWN": kVK_DownArrow,
            "↩": kVK_Return, "RETURN": kVK_Return, "ENTER": kVK_Return,
            "⌫": kVK_Delete, "DELETE": kVK_Delete, "BACKSPACE": kVK_Delete,
            "U": kVK_ANSI_U, "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K,
            "D": kVK_ANSI_D, "F": kVK_ANSI_F, "G": kVK_ANSI_G,
            "E": kVK_ANSI_E, "T": kVK_ANSI_T, "C": kVK_ANSI_C,
        ]
        guard let code = table[key] else { return nil }
        return UInt32(code)
    }
}

public enum MagnetLayouts {
    public static let defaults: [SnapAction: KeyCombo] = [
        .leftHalf: KeyCombo(keyCode: UInt32(kVK_LeftArrow), modifiers: KeyCombo.controlOption),
        .rightHalf: KeyCombo(keyCode: UInt32(kVK_RightArrow), modifiers: KeyCombo.controlOption),
        .topHalf: KeyCombo(keyCode: UInt32(kVK_UpArrow), modifiers: KeyCombo.controlOption),
        .bottomHalf: KeyCombo(keyCode: UInt32(kVK_DownArrow), modifiers: KeyCombo.controlOption),
        .topLeft: KeyCombo(keyCode: UInt32(kVK_ANSI_U), modifiers: KeyCombo.controlOption),
        .topRight: KeyCombo(keyCode: UInt32(kVK_ANSI_I), modifiers: KeyCombo.controlOption),
        .bottomLeft: KeyCombo(keyCode: UInt32(kVK_ANSI_J), modifiers: KeyCombo.controlOption),
        .bottomRight: KeyCombo(keyCode: UInt32(kVK_ANSI_K), modifiers: KeyCombo.controlOption),
        .leftThird: KeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: KeyCombo.controlOption),
        .centreThird: KeyCombo(keyCode: UInt32(kVK_ANSI_F), modifiers: KeyCombo.controlOption),
        .rightThird: KeyCombo(keyCode: UInt32(kVK_ANSI_G), modifiers: KeyCombo.controlOption),
        .leftTwoThirds: KeyCombo(keyCode: UInt32(kVK_ANSI_E), modifiers: KeyCombo.controlOption),
        .rightTwoThirds: KeyCombo(keyCode: UInt32(kVK_ANSI_T), modifiers: KeyCombo.controlOption),
        .maximise: KeyCombo(keyCode: UInt32(kVK_Return), modifiers: KeyCombo.controlOption),
        .centre: KeyCombo(keyCode: UInt32(kVK_ANSI_C), modifiers: KeyCombo.controlOption),
        .restore: KeyCombo(keyCode: UInt32(kVK_Delete), modifiers: KeyCombo.controlOption),
        .nextDisplay: KeyCombo(keyCode: UInt32(kVK_RightArrow), modifiers: KeyCombo.controlOptionCommand),
        .previousDisplay: KeyCombo(keyCode: UInt32(kVK_LeftArrow), modifiers: KeyCombo.controlOptionCommand),
    ]

    public static func table(overrides: [String: String]) -> [SnapAction: KeyCombo] {
        var table = defaults
        for (rawAction, rawCombo) in overrides {
            guard let action = SnapAction(rawValue: rawAction) else {
                Log.error("unknown shortcut action in config: \(rawAction)")
                continue
            }
            let trimmed = rawCombo.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.lowercased() == "off" || trimmed.lowercased() == "none" {
                table.removeValue(forKey: action)
                continue
            }
            guard let combo = KeyCombo.parse(trimmed) else {
                Log.error("unreadable shortcut in config: \(rawAction)=\(rawCombo)")
                continue
            }
            table[action] = combo
        }
        return table
    }

    public static func frame(for action: SnapAction, work: CGRect, current: CGRect) -> CGRect? {
        let halfWidth = (work.width / 2).rounded()
        let halfHeight = (work.height / 2).rounded()

        switch action {
        case .leftHalf:
            return CGRect(x: work.minX, y: work.minY, width: halfWidth, height: work.height)
        case .rightHalf:
            return CGRect(x: work.minX + halfWidth, y: work.minY, width: work.width - halfWidth, height: work.height)
        case .topHalf:
            return CGRect(x: work.minX, y: work.minY, width: work.width, height: halfHeight)
        case .bottomHalf:
            return CGRect(x: work.minX, y: work.minY + halfHeight, width: work.width, height: work.height - halfHeight)
        case .topLeft:
            return CGRect(x: work.minX, y: work.minY, width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: work.minX + halfWidth, y: work.minY, width: work.width - halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: work.minX, y: work.minY + halfHeight, width: halfWidth, height: work.height - halfHeight)
        case .bottomRight:
            return CGRect(x: work.minX + halfWidth, y: work.minY + halfHeight,
                          width: work.width - halfWidth, height: work.height - halfHeight)
        case .leftThird:
            return Geo.slice(work, columns: 3, index: 0)
        case .centreThird:
            return Geo.slice(work, columns: 3, index: 1)
        case .rightThird:
            return Geo.slice(work, columns: 3, index: 2)
        case .leftTwoThirds:
            return Geo.slice(work, columns: 3, index: 0, span: 2)
        case .rightTwoThirds:
            return Geo.slice(work, columns: 3, index: 1, span: 2)
        case .maximise:
            return work
        case .centre:
            return Geo.centre(current.size, in: work)
        case .restore, .nextDisplay, .previousDisplay:
            return nil
        }
    }
}
