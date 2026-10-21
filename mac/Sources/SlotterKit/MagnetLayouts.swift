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

    private static let namedKeys: [String: UInt32] = {
        var values: [String: UInt32] = [
            "←": UInt32(kVK_LeftArrow), "→": UInt32(kVK_RightArrow),
            "↑": UInt32(kVK_UpArrow), "↓": UInt32(kVK_DownArrow),
            "↩": UInt32(kVK_Return), "RETURN": UInt32(kVK_Return), "ENTER": UInt32(kVK_Return),
            "⌫": UInt32(kVK_Delete), "DELETE": UInt32(kVK_Delete), "BACKSPACE": UInt32(kVK_Delete),
            "⌦": UInt32(kVK_ForwardDelete), "FORWARD DELETE": UInt32(kVK_ForwardDelete),
            "SPACE": UInt32(kVK_Space), "TAB": UInt32(kVK_Tab),
            "`": UInt32(kVK_ANSI_Grave), "-": UInt32(kVK_ANSI_Minus), "=": UInt32(kVK_ANSI_Equal),
            "[": UInt32(kVK_ANSI_LeftBracket), "]": UInt32(kVK_ANSI_RightBracket),
            "\\": UInt32(kVK_ANSI_Backslash), ";": UInt32(kVK_ANSI_Semicolon),
            "'": UInt32(kVK_ANSI_Quote), ",": UInt32(kVK_ANSI_Comma),
            ".": UInt32(kVK_ANSI_Period), "/": UInt32(kVK_ANSI_Slash),
            "LEFT": UInt32(kVK_LeftArrow), "RIGHT": UInt32(kVK_RightArrow),
            "UP": UInt32(kVK_UpArrow), "DOWN": UInt32(kVK_DownArrow),
        ]
        let letters: [(String, Int)] = [
            ("A", kVK_ANSI_A), ("B", kVK_ANSI_B), ("C", kVK_ANSI_C), ("D", kVK_ANSI_D),
            ("E", kVK_ANSI_E), ("F", kVK_ANSI_F), ("G", kVK_ANSI_G), ("H", kVK_ANSI_H),
            ("I", kVK_ANSI_I), ("J", kVK_ANSI_J), ("K", kVK_ANSI_K), ("L", kVK_ANSI_L),
            ("M", kVK_ANSI_M), ("N", kVK_ANSI_N), ("O", kVK_ANSI_O), ("P", kVK_ANSI_P),
            ("Q", kVK_ANSI_Q), ("R", kVK_ANSI_R), ("S", kVK_ANSI_S), ("T", kVK_ANSI_T),
            ("U", kVK_ANSI_U), ("V", kVK_ANSI_V), ("W", kVK_ANSI_W), ("X", kVK_ANSI_X),
            ("Y", kVK_ANSI_Y), ("Z", kVK_ANSI_Z),
        ]
        for (name, code) in letters { values[name] = UInt32(code) }
        let digits: [(String, Int)] = [
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
            ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7),
            ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
        ]
        for (name, code) in digits { values[name] = UInt32(code) }
        for number in 1...20 {
            if let code = functionKey(number) { values["F\(number)"] = code }
        }
        return values
    }()

    private static let displayNames: [UInt32: String] = {
        var values: [UInt32: String] = [:]
        for (name, code) in namedKeys {
            if name.count == 1 || name.hasPrefix("F") { values[code] = name }
        }
        values[UInt32(kVK_LeftArrow)] = "←"
        values[UInt32(kVK_RightArrow)] = "→"
        values[UInt32(kVK_UpArrow)] = "↑"
        values[UInt32(kVK_DownArrow)] = "↓"
        values[UInt32(kVK_Return)] = "↩"
        values[UInt32(kVK_Delete)] = "⌫"
        values[UInt32(kVK_ForwardDelete)] = "⌦"
        values[UInt32(kVK_Space)] = "Space"
        values[UInt32(kVK_Tab)] = "Tab"
        return values
    }()

    public var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + KeyCombo.name(for: keyCode)
    }

    public static func name(for keyCode: UInt32) -> String {
        displayNames[keyCode] ?? "key \(keyCode)"
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
        let rawKey = remainder.trimmingCharacters(in: .whitespaces)
        let code = namedKeys[rawKey.uppercased()] ?? namedKeys[rawKey]
            ?? (rawKey.lowercased().hasPrefix("key ") ? UInt32(rawKey.dropFirst(4)) : nil)
        guard modifiers != 0, let code else { return nil }
        return KeyCombo(keyCode: code, modifiers: modifiers)
    }

    private static func functionKey(_ number: Int) -> UInt32? {
        let codes: [Int] = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
                            kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16,
                            kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        guard codes.indices.contains(number - 1) else { return nil }
        return UInt32(codes[number - 1])
    }
}

public enum ShortcutRules {
    public static func conflict(for combo: KeyCombo, excluding action: SnapAction,
                                overrides: [String: String]) -> SnapAction? {
        MagnetLayouts.table(overrides: overrides).first { pair in
            pair.key != action && pair.value == combo
        }?.key
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
