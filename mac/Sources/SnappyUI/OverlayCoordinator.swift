import AppKit
import SnappyKit
import SwiftUI

struct OverlayView: View {
    let caption: String
    let highlighted: Bool

    var body: some View {
        GeometryReader { proxy in
            let arm = max(10, min(24, min(proxy.size.width, proxy.size.height) / 6))
            ZStack {
                Rectangle()
                    .fill(Color(theme: Theme.soft))
                    .opacity(highlighted ? 0.92 : 0.82)

                Rectangle()
                    .strokeBorder(Color(theme: Theme.accent), lineWidth: highlighted ? 3 : 2)
                    .padding(1)

                CornerBrackets(arm: arm)
                    .stroke(Color(theme: Theme.accent), style: StrokeStyle(lineWidth: 4, lineCap: .round))

                Text(caption)
                    .font(.system(size: Theme.Size.large, weight: .semibold))
                    .foregroundStyle(Color(theme: Theme.text))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
            }
        }
    }
}

struct CornerBrackets: Shape {
    let arm: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.insetBy(dx: 3, dy: 3)
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
        return path
    }
}

@MainActor
final class OverlayPanel {
    let panel: NSPanel
    private let hosting: NSHostingView<OverlayView>
    private var caption = ""
    private var highlighted = false

    init() {
        hosting = NSHostingView(rootView: OverlayView(caption: "", highlighted: false))
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.alphaValue = 0
        panel.contentView = hosting
    }

    func configure(frame: NSRect, caption: String, highlighted: Bool) {
        if self.caption != caption || self.highlighted != highlighted {
            self.caption = caption
            self.highlighted = highlighted
            hosting.rootView = OverlayView(caption: caption, highlighted: highlighted)
        }
        panel.setFrame(frame, display: false)
    }

    func setHighlighted(_ value: Bool) {
        guard highlighted != value else { return }
        highlighted = value
        hosting.rootView = OverlayView(caption: caption, highlighted: value)
    }

    func prewarm() {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
    }

    func reveal(duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        panel.orderOut(nil)
        panel.alphaValue = 0
    }
}

@MainActor
public final class OverlayCoordinator {
    public static let shared = OverlayCoordinator()

    private var pool: [OverlayPanel] = []
    private var active: [Int: OverlayPanel] = [:]
    private var roaming: OverlayPanel?
    private var roamingTargetID: Int?

    public init() {}

    public func present(zones: [SnapTarget], flipY: CGFloat) {
        dismiss()
        for target in zones {
            let panel = borrow()
            panel.configure(frame: Geo.cocoa(fromAX: target.frame, flipY: flipY),
                            caption: target.caption,
                            highlighted: false)
            panel.prewarm()
            active[target.id] = panel
        }
    }

    public func reveal() {
        for panel in active.values { panel.reveal(duration: 0.12) }
    }

    public func highlight(_ target: SnapTarget?, flipY: CGFloat) {
        for (id, panel) in active { panel.setHighlighted(id == target?.id) }

        guard let target, target.isEdge else {
            hideRoaming()
            return
        }

        let frame = Geo.cocoa(fromAX: target.frame, flipY: flipY)
        if let roaming, roamingTargetID != nil {
            roaming.configure(frame: roaming.panel.frame, caption: target.caption, highlighted: true)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                roaming.panel.animator().setFrame(frame, display: true)
            }
        } else {
            let panel = roaming ?? borrow()
            panel.configure(frame: frame, caption: target.caption, highlighted: true)
            panel.prewarm()
            panel.reveal(duration: 0.10)
            roaming = panel
        }
        roamingTargetID = target.id
    }

    public func dismiss() {
        for panel in active.values {
            panel.hide()
            pool.append(panel)
        }
        active.removeAll()
        hideRoaming()
    }

    public func dismissAnimated() {
        let leaving = Array(active.values) + (roaming.map { [$0] } ?? [])
        active.removeAll()
        roaming = nil
        roamingTargetID = nil

        guard !leaving.isEmpty else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.10
            for panel in leaving { panel.panel.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                for panel in leaving { panel.hide() }
                self?.pool.append(contentsOf: leaving)
            }
        })
    }

    private func hideRoaming() {
        guard let roaming else { return }
        roaming.hide()
        pool.append(roaming)
        self.roaming = nil
        roamingTargetID = nil
    }

    private func borrow() -> OverlayPanel {
        if let reused = pool.popLast() { return reused }
        return OverlayPanel()
    }
}
