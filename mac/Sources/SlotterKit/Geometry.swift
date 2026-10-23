import AppKit

public enum Geo {
    @MainActor
    public static var mainFlipY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    public static func ax(fromCocoa rect: CGRect, flipY: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: flipY - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func cocoa(fromAX rect: CGRect, flipY: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: flipY - rect.maxY, width: rect.width, height: rect.height)
    }

    @MainActor
    public static func cocoa(fromAX rect: CGRect) -> CGRect {
        cocoa(fromAX: rect, flipY: mainFlipY)
    }

    public static func integral(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x.rounded(),
               y: rect.origin.y.rounded(),
               width: max(1, rect.width.rounded()),
               height: max(1, rect.height.rounded()))
    }

    public static func rect(percentX x: Double, y: Double, w: Double, h: Double, in work: CGRect) -> CGRect {
        integral(CGRect(x: work.minX + work.width * CGFloat(x) / 100,
                        y: work.minY + work.height * CGFloat(y) / 100,
                        width: work.width * CGFloat(w) / 100,
                        height: work.height * CGFloat(h) / 100))
    }

    public static func fraction(of rect: CGRect, in outer: CGRect) -> CGRect {
        guard outer.width > 0, outer.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return CGRect(x: (rect.minX - outer.minX) / outer.width,
                      y: (rect.minY - outer.minY) / outer.height,
                      width: rect.width / outer.width,
                      height: rect.height / outer.height)
    }

    public static func denormalize(_ unit: CGRect, into outer: CGRect) -> CGRect {
        integral(CGRect(x: outer.minX + unit.minX * outer.width,
                        y: outer.minY + unit.minY * outer.height,
                        width: unit.width * outer.width,
                        height: unit.height * outer.height))
    }

    public static func clamp(_ rect: CGRect, into outer: CGRect) -> CGRect {
        var result = rect
        result.size.width = min(result.width, outer.width)
        result.size.height = min(result.height, outer.height)
        result.origin.x = min(max(result.minX, outer.minX), outer.maxX - result.width)
        result.origin.y = min(max(result.minY, outer.minY), outer.maxY - result.height)
        return result
    }

    public static func centre(_ size: CGSize, in outer: CGRect) -> CGRect {
        clamp(CGRect(x: outer.midX - size.width / 2,
                     y: outer.midY - size.height / 2,
                     width: size.width,
                     height: size.height), into: outer)
    }

    public static func windowOrigin(_ proposed: CGPoint, actualSize: CGSize, zone: CGRect, workArea: CGRect) -> CGPoint {
        let horizontal = actualSize.width > zone.width ? workArea : zone
        let vertical = actualSize.height > zone.height ? workArea : zone
        return CGPoint(x: min(max(proposed.x, horizontal.minX), max(horizontal.minX, horizontal.maxX - actualSize.width)),
                       y: min(max(proposed.y, vertical.minY), max(vertical.minY, vertical.maxY - actualSize.height)))
    }

    public static func slice(_ outer: CGRect, columns: Int, index: Int, span: Int = 1) -> CGRect {
        let start = (outer.width * CGFloat(index) / CGFloat(columns)).rounded()
        let end = (outer.width * CGFloat(index + span) / CGFloat(columns)).rounded()
        return CGRect(x: outer.minX + start, y: outer.minY, width: max(1, end - start), height: outer.height)
    }

    public static func describe(_ rect: CGRect) -> String {
        "(\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height)))"
    }

    public static func matches(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.maxX - rhs.maxX) <= tolerance
            && abs(lhs.maxY - rhs.maxY) <= tolerance
    }
}
