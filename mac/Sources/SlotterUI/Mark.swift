import AppKit
import SwiftUI

/// The 16px glyph from `Slotter-glyph.svg`: a U-shaped bezel open at the top, the panel rising
/// through the gap, a neck and a foot. Whole pixels only, so it stays sharp at 16 and 32.
public enum Mark {
    static let rects: [[CGRect]] = [
        [CGRect(x: 1, y: 3, width: 4, height: 1), CGRect(x: 11, y: 3, width: 4, height: 1),
         CGRect(x: 1, y: 4, width: 1, height: 8), CGRect(x: 14, y: 4, width: 1, height: 8),
         CGRect(x: 2, y: 11, width: 12, height: 1)],
        [CGRect(x: 6, y: 1, width: 4, height: 9)],
        [CGRect(x: 7, y: 12, width: 2, height: 2), CGRect(x: 4, y: 14, width: 8, height: 1)],
    ]

    public static func statusItemImage(points: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: points, height: points), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.scaleBy(x: points / 16, y: points / 16)
            ctx.setFillColor(NSColor.black.cgColor)
            for rect in rects.joined() { ctx.fill(rect) }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The bundle's icon, which `build.sh` renders from `Slotter.svg`. Outside a bundle there is
    /// no icon to show, and the glyph stands in.
    public static var appIcon: NSImage? {
        Bundle.main.url(forResource: "Slotter", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
    }
}

struct GlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        var path = Path()
        for unit in Mark.rects.joined() {
            path.addRect(CGRect(x: rect.minX + unit.minX * scale, y: rect.minY + unit.minY * scale,
                                width: unit.width * scale, height: unit.height * scale))
        }
        return path
    }
}

struct Glyph: View {
    var size: CGFloat = 16

    var body: some View {
        GlyphShape().frame(width: size, height: size)
    }
}
