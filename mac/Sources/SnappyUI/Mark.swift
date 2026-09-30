import AppKit

public enum Mark {
    public static let orange = CGColor(srgbRed: 0xC5 / 255, green: 0x4F / 255, blue: 0x16 / 255, alpha: 1)
    public static let cream = CGColor(srgbRed: 0xFF / 255, green: 0xFD / 255, blue: 0xF8 / 255, alpha: 1)
    public static let pale = CGColor(srgbRed: 0xFF / 255, green: 0xCA / 255, blue: 0xA9 / 255, alpha: 1)

    public static func drawAppIcon(in ctx: CGContext, side: CGFloat) {
        let s = side / 1024
        ctx.saveGState()
        ctx.scaleBy(x: s, y: s)

        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = superellipse(in: body, exponent: 5)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28))
        ctx.addPath(shape)
        ctx.setFillColor(orange)
        ctx.fillPath()
        ctx.restoreGState()

        let cell = body.width * 0.26
        let gap = body.width * 0.06
        let span = cell * 2 + gap
        let originX = body.midX - span / 2
        let originY = body.midY - span / 2
        let radius = body.width * 0.05

        for (index, point) in [(0, 1), (1, 1), (0, 0), (1, 0)].enumerated() {
            let rect = CGRect(x: originX + CGFloat(point.0) * (cell + gap),
                              y: originY + CGFloat(point.1) * (cell + gap),
                              width: cell, height: cell)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setFillColor(index == 3 ? pale : cream)
            ctx.fillPath()
        }

        ctx.restoreGState()
    }

    public static func appIcon(side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawAppIcon(in: ctx, side: side)
            return true
        }
    }

    public static func statusItemImage(points: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: points, height: points), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let s = points / 18
            ctx.saveGState()
            ctx.scaleBy(x: s, y: s)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.6)
            let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            for (index, point) in [(0, 1), (1, 1), (0, 0), (1, 0)].enumerated() {
                let rect = CGRect(x: 1 + CGFloat(point.0) * 9, y: 1 + CGFloat(point.1) * 9, width: 7, height: 7)
                let path = CGPath(roundedRect: index == 3 ? rect.insetBy(dx: 0.8, dy: 0.8) : rect,
                                  cornerWidth: 1.6, cornerHeight: 1.6, transform: nil)
                ctx.addPath(path)
                if index == 3 {
                    ctx.setStrokeColor(black)
                    ctx.strokePath()
                } else {
                    ctx.setFillColor(black)
                    ctx.fillPath()
                }
            }
            ctx.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func superellipse(in rect: CGRect, exponent: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let a = rect.width / 2
        let b = rect.height / 2
        let cx = rect.midX
        let cy = rect.midY
        let steps = 512
        let power = 2 / exponent
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
            let c = cos(t)
            let s = sin(t)
            let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), power)
            let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), power)
            if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}
