import DeskTheme
import SnappyKit
import SwiftUI

struct CanvasLayout {
    var scale: CGFloat
    var offset: CGPoint
    var bounds: CGRect

    init(displays: [DisplayInfo], size: CGSize, insets: NSEdgeInsets) {
        let union = displays.reduce(CGRect.null) { $0.union($1.frameAX) }
        bounds = union.isNull ? CGRect(x: 0, y: 0, width: 1, height: 1) : union
        let usable = CGSize(width: max(1, size.width - insets.left - insets.right),
                            height: max(1, size.height - insets.top - insets.bottom))
        scale = min(usable.width / bounds.width, usable.height / bounds.height)
        let drawn = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        offset = CGPoint(x: insets.left + (usable.width - drawn.width) / 2 - bounds.minX * scale,
                         y: insets.top + (usable.height - drawn.height) / 2 - bounds.minY * scale)
    }

    func rect(_ ax: CGRect) -> CGRect {
        CGRect(x: ax.minX * scale + offset.x,
               y: ax.minY * scale + offset.y,
               width: ax.width * scale,
               height: ax.height * scale)
    }

    func axPoint(_ view: CGPoint) -> CGPoint {
        CGPoint(x: (view.x - offset.x) / scale, y: (view.y - offset.y) / scale)
    }
}

struct MonitorCanvasView: View {
    @Bindable var model: SettingsModel
    @FocusState private var focused: Bool

    private let insets = NSEdgeInsets(top: 52, left: 40, bottom: 40, right: 40)

    var body: some View {
        GeometryReader { proxy in
            let displays = DisplayRegistry.current.displays
            let layout = CanvasLayout(displays: displays, size: proxy.size, insets: insets)

            Canvas { context, _ in
                for display in displays { draw(display: display, in: &context, layout: layout) }
            }
            .background(Color(theme: Theme.canvas))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                focused = true
                select(at: layout.axPoint(value.location), displays: displays)
            })
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { model.moveZoneSelection(by: -1); return .handled }
            .onKeyPress(.upArrow) { model.moveZoneSelection(by: -1); return .handled }
            .onKeyPress(.rightArrow) { model.moveZoneSelection(by: 1); return .handled }
            .onKeyPress(.downArrow) { model.moveZoneSelection(by: 1); return .handled }
            .onKeyPress(.pageUp) { model.moveDisplaySelection(by: -1); return .handled }
            .onKeyPress(.pageDown) { model.moveDisplaySelection(by: 1); return .handled }
            .overlay(alignment: .bottom) {
                if model.selectedWorkspace != nil {
                    Text(verbatim: "Click a zone to edit it · arrows move between zones")
                        .font(.system(size: Theme.Size.micro))
                        .foregroundStyle(Color(theme: Theme.dim))
                        .padding(.bottom, 14)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color(theme: Theme.accent).opacity(0.35), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func select(at point: CGPoint, displays: [DisplayInfo]) {
        guard let display = displays.first(where: { $0.frameAX.contains(point) }) else { return }
        model.selectedDisplayID = display.id

        guard let workspace = model.selectedWorkspace else { return }
        let snapshot = DisplayRegistry.current
        for index in workspace.zones.indices.reversed() {
            guard let rect = ZoneGeometry.bounds(for: workspace.zones[index], in: snapshot) else { continue }
            if rect.contains(point) {
                model.selectedZoneIndex = index
                return
            }
        }
        model.selectedZoneIndex = nil
    }

    private func draw(display: DisplayInfo, in context: inout GraphicsContext, layout: CanvasLayout) {
        let frame = layout.rect(display.frameAX)
        let selectedMonitor = display.id == model.selectedDisplayID
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous).path(in: frame)

        context.fill(shape, with: .color(Color(theme: Theme.monitorFill)))

        for step in 1..<10 {
            let fraction = CGFloat(step) / 10
            var line = Path()
            line.move(to: CGPoint(x: frame.minX + frame.width * fraction, y: frame.minY + 1))
            line.addLine(to: CGPoint(x: frame.minX + frame.width * fraction, y: frame.maxY - 1))
            context.stroke(line, with: .color(Color(theme: Theme.grid)), lineWidth: 1)

            var horizontal = Path()
            horizontal.move(to: CGPoint(x: frame.minX + 1, y: frame.minY + frame.height * fraction))
            horizontal.addLine(to: CGPoint(x: frame.maxX - 1, y: frame.minY + frame.height * fraction))
            context.stroke(horizontal, with: .color(Color(theme: Theme.grid)), lineWidth: 1)
        }

        let snapshot = DisplayRegistry.current
        let zones = model.selectedWorkspace?.zones ?? []
        var drawnHere = 0

        for (index, zone) in zones.enumerated() {
            guard DisplayRegistry.resolve(zone.monitor, in: snapshot)?.id == display.id,
                  let axRect = ZoneGeometry.bounds(for: zone, in: snapshot) else { continue }
            drawnHere += 1

            let rect = layout.rect(axRect).insetBy(dx: 2, dy: 2)
            let selected = model.selectedZoneIndex == index
            let zoneShape = RoundedRectangle(cornerRadius: 5, style: .continuous).path(in: rect)

            context.fill(zoneShape, with: .color(Color(theme: selected ? Theme.zoneFillSelected : Theme.zoneFill)))
            context.stroke(zoneShape,
                           with: .color(Color(theme: selected ? Theme.accent : Theme.rule)),
                           lineWidth: selected ? 2 : 1)

            drawZoneLabel(index: index, program: zone.program, rect: rect, selected: selected, in: &context)
            if selected { drawCorners(in: &context, rect: rect) }
        }

        context.stroke(shape,
                       with: .color(Color(theme: selectedMonitor ? Theme.accent : Theme.rule)),
                       lineWidth: selectedMonitor ? 2 : 1)

        if drawnHere > 0 {
            drawStateBadge(zoneCount: drawnHere, in: &context, monitorFrame: frame)
        }

        if drawnHere == 0 {
            let hint = context.resolve(Text(verbatim: model.selectedWorkspace == nil
                ? "Select a workspace to lay out its zones"
                : "Apply a preset to lay out this monitor")
                .font(.system(size: Theme.Size.body))
                .foregroundStyle(Color(theme: Theme.dim)))
            context.draw(hint, at: CGPoint(x: frame.midX, y: frame.midY), anchor: .center)
        }

        let name = context.resolve(Text(verbatim: display.name)
            .font(.system(size: Theme.Size.body, weight: .semibold))
            .foregroundStyle(Color(theme: selectedMonitor ? Theme.accent : Theme.text)))
        let nameSize = name.measure(in: CGSize(width: frame.width, height: 40))
        context.draw(name, at: CGPoint(x: frame.minX, y: frame.minY - 26), anchor: .topLeading)

        let dimensions = "\(Int(display.pointSize.width)) × \(Int(display.pointSize.height))"
        let size = context.resolve(Text(verbatim: dimensions)
            .font(.system(size: Theme.Size.small).monospacedDigit())
            .foregroundStyle(Color(theme: Theme.dim)))
        context.draw(size, at: CGPoint(x: frame.minX + nameSize.width + 10, y: frame.minY - 25), anchor: .topLeading)
    }

    private func drawZoneLabel(index: Int,
                               program: String?,
                               rect: CGRect,
                               selected: Bool,
                               in context: inout GraphicsContext) {
        let hasProgram = !(program ?? "").isEmpty
        let title = context.resolve(Text(verbatim: "Zone \(index + 1)")
            .font(.system(size: Theme.Size.body, weight: .semibold))
            .foregroundStyle(Color(theme: selected ? Theme.accent : Theme.text)))
        let titleSize = title.measure(in: rect.size)
        guard titleSize.width < rect.width - 16, rect.height > 34 else { return }

        let offset: CGFloat = hasProgram ? 9 : 0
        context.draw(title, at: CGPoint(x: rect.midX, y: rect.midY - offset), anchor: .center)

        guard hasProgram, let program, rect.height > 52 else { return }
        let subtitle = context.resolve(Text(verbatim: program)
            .font(.system(size: Theme.Size.small))
            .foregroundStyle(Color(theme: Theme.dim)))
        guard subtitle.measure(in: rect.size).width < rect.width - 16 else { return }
        context.draw(subtitle, at: CGPoint(x: rect.midX, y: rect.midY + 9), anchor: .center)
    }

    /// A pill giving this monitor's live state: how many of the selected workspace's zones it is
    /// currently drawing. Matches Desk's badge-and-dot component (a dot rotating green for "live",
    /// on a ground-independent dark pill, since it sits on top of the monitor's own drawing
    /// rather than taking colour from the app's ground). Drawn with `GraphicsContext` primitives,
    /// like every other label on this canvas, rather than a SwiftUI `DeskBadge` view — `Canvas`
    /// only composites arbitrary SwiftUI views via its symbol-resolution API, which would be a
    /// bigger change than this presentation pass calls for.
    private func drawStateBadge(zoneCount: Int, in context: inout GraphicsContext, monitorFrame: CGRect) {
        let label = zoneCount == 1 ? "1 zone" : "\(zoneCount) zones"
        let text = context.resolve(Text(verbatim: label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color(nsColor: Desk.badgeInk)))
        let textSize = text.measure(in: CGSize(width: 160, height: 20))

        let dotDiameter: CGFloat = 5
        let gap: CGFloat = 5
        let horizontalPadding: CGFloat = 8
        let pillHeight: CGFloat = 20
        let pillWidth = horizontalPadding * 2 + dotDiameter + gap + textSize.width
        let pillRect = CGRect(x: monitorFrame.minX + 6, y: monitorFrame.minY + 6,
                              width: pillWidth, height: pillHeight)

        context.fill(RoundedRectangle(cornerRadius: pillHeight / 2, style: .continuous).path(in: pillRect),
                     with: .color(Color(nsColor: Desk.badgeGround)))

        let dotRect = CGRect(x: pillRect.minX + horizontalPadding, y: pillRect.midY - dotDiameter / 2,
                             width: dotDiameter, height: dotDiameter)
        context.fill(Path(ellipseIn: dotRect), with: .color(Color(desk: Desk.live)))

        context.draw(text, at: CGPoint(x: dotRect.maxX + gap, y: pillRect.midY), anchor: .leading)
    }

    private func drawCorners(in context: inout GraphicsContext, rect: CGRect) {
        let arm = max(5, min(14, min(rect.width, rect.height) / 4))
        let inset = rect.insetBy(dx: 4, dy: 4)
        var path = Path()
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: inset.minX, y: inset.minY + arm), CGPoint(x: inset.minX, y: inset.minY),
             CGPoint(x: inset.minX + arm, y: inset.minY)),
            (CGPoint(x: inset.maxX - arm, y: inset.minY), CGPoint(x: inset.maxX, y: inset.minY),
             CGPoint(x: inset.maxX, y: inset.minY + arm)),
            (CGPoint(x: inset.maxX, y: inset.maxY - arm), CGPoint(x: inset.maxX, y: inset.maxY),
             CGPoint(x: inset.maxX - arm, y: inset.maxY)),
            (CGPoint(x: inset.minX + arm, y: inset.maxY), CGPoint(x: inset.minX, y: inset.maxY),
             CGPoint(x: inset.minX, y: inset.maxY - arm)),
        ]
        for corner in corners {
            path.move(to: corner.0)
            path.addLine(to: corner.1)
            path.addLine(to: corner.2)
        }
        context.stroke(path, with: .color(Color(theme: Theme.accent)),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }
}
