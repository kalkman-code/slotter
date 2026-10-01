import AppKit
import SlotterKit
import SwiftUI

private let P = T.palette

/// One zone drawn on the real screen while a window is dragged: an outline over a dimmed
/// patch of desktop, and the zone under the cursor filled, thickened and yellow. No bezel art.
public struct OverlayView: View {
    let chip: String
    let highlighted: Bool

    public init(chip: String, highlighted: Bool) {
        self.chip = chip
        self.highlighted = highlighted
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: T.radii.chip).fill(P.overlayDim)
            if highlighted { RoundedRectangle(cornerRadius: T.radii.chip).fill(P.overlayLit) }
            RoundedRectangle(cornerRadius: T.radii.chip)
                .strokeBorder(highlighted ? P.selection : P.overlayLine, lineWidth: highlighted ? 3 : 2)
            if !chip.isEmpty {
                Text(chip)
                    .font(T.font(T.type.switcher, .extraBold))
                    .foregroundStyle(highlighted ? P.onSelection : P.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: T.radii.chip).fill(highlighted ? P.selection : P.zone))
                    .padding(10)
            }
        }
        .padding(3)
    }

    static func chip(for target: SnapTarget) -> String {
        guard case .zone(let index) = target.source else { return target.caption }
        let name = target.caption.components(separatedBy: " · ").dropFirst().joined(separator: " · ")
        return "\(index + 1) \(name == "ready for any app" ? "Any app" : name)"
    }
}

@MainActor
final class OverlayPanel {
    let panel: NSPanel
    private let hosting: NSHostingView<OverlayView>
    private var chip = ""
    private var highlighted = false

    init() {
        hosting = NSHostingView(rootView: OverlayView(chip: "", highlighted: false))
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

    func configure(frame: NSRect, chip: String, highlighted: Bool) {
        if self.chip != chip || self.highlighted != highlighted {
            self.chip = chip
            self.highlighted = highlighted
            hosting.rootView = OverlayView(chip: chip, highlighted: highlighted)
        }
        panel.setFrame(frame, display: false)
    }

    func setHighlighted(_ value: Bool) {
        guard highlighted != value else { return }
        highlighted = value
        hosting.rootView = OverlayView(chip: chip, highlighted: value)
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
                            chip: OverlayView.chip(for: target),
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
            roaming.configure(frame: roaming.panel.frame, chip: OverlayView.chip(for: target), highlighted: true)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                roaming.panel.animator().setFrame(frame, display: true)
            }
        } else {
            let panel = roaming ?? borrow()
            panel.configure(frame: frame, chip: OverlayView.chip(for: target), highlighted: true)
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
