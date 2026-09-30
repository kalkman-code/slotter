import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: snappy-icongen <source.svg> <output.iconset>\n".utf8))
    exit(2)
}

let svgURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let mark = NSImage(contentsOf: svgURL) else {
    FileHandle.standardError.write(Data("failed to load \(svgURL.path)\n".utf8))
    exit(1)
}

let fm = FileManager.default
try? fm.removeItem(at: outputURL)
try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)

let slots: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

for slot in slots {
    let pixels = slot.points * slot.scale
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixels,
                                     pixelsHigh: pixels,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else {
        FileHandle.standardError.write(Data("failed to allocate \(pixels)px bitmap\n".utf8))
        exit(1)
    }
    rep.size = NSSize(width: pixels, height: pixels)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.imageInterpolation = .high
    // NSImage backed by SVG is resolution-independent, like a PDF image rep: this re-rasterizes
    // the vector mark at the target size rather than scaling a fixed-size bitmap.
    mark.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
              from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    let suffix = slot.scale == 1 ? "" : "@\(slot.scale)x"
    let name = "icon_\(slot.points)x\(slot.points)\(suffix).png"
    try png.write(to: outputURL.appending(path: name))
}

print("wrote \(slots.count) slots to \(outputURL.path)")
