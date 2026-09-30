import AppKit

public enum Sym {
    private static let table: [String: String] = [
        "workspace": "square.grid.2x2",
        "set": "square.grid.2x2.fill",
        "settings": "gearshape",
        "startup": "power",
        "reload": "arrow.clockwise",
        "hotkey": "command",
        "windows": "macwindow.on.rectangle",
        "close": "xmark.circle",
        "kill": "exclamationmark.triangle.fill",
        "exit": "escape",
        "add": "plus",
        "edit": "pencil",
        "rename": "pencil",
        "remove": "minus",
        "cancel": "xmark",
        "splitv": "rectangle.split.2x1",
        "splith": "rectangle.split.1x2",
        "reset": "arrow.counterclockwise",
        "program": "app.dashed",
        "save": "checkmark",
        "browse": "folder",
        "launch": "play.fill",
        "monitor": "display",
        "zone": "rectangle.dashed",
    ]

    public static func name(_ glyph: String) -> String { table[glyph] ?? "questionmark" }

    public static func image(_ glyph: String, tint: NSColor? = nil, points: CGFloat = 14) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name(glyph), accessibilityDescription: glyph) else { return nil }
        let configured = base.withSymbolConfiguration(.init(pointSize: points, weight: .medium))
        guard let image = configured else { return base }
        guard let tint else {
            image.isTemplate = true
            return image
        }
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            tint.set()
            image.draw(in: rect)
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }
}
