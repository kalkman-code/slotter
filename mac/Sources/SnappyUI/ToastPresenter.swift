import AppKit
import SnappyKit
import SwiftUI

public struct ToastContent: Sendable, Equatable {
    public var title: String
    public var body: String
    public var success: Bool

    public init(title: String, body: String, success: Bool) {
        self.title = title
        self.body = body
        self.success = success
    }
}

struct ToastView: View {
    let content: ToastContent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: Sym.name(content.success ? "launch" : "kill"))
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color(theme: content.success ? Theme.accent : Theme.danger))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(content.title)
                    .font(.system(size: Theme.Size.body, weight: .semibold))
                    .foregroundStyle(Color(theme: Theme.text))
                    .lineLimit(1)
                Text(content.body)
                    .font(.system(size: Theme.Size.small))
                    .foregroundStyle(Color(theme: Theme.dim))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(theme: Theme.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(theme: Theme.rule), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .padding(10)
    }
}

@MainActor
public final class ToastPresenter {
    public static let shared = ToastPresenter()

    private var panel: NSPanel?
    private var dismissal: DispatchWorkItem?

    public init() {}

    public func show(_ content: ToastContent) {
        dismiss(animated: false)

        let hosting = NSHostingView(rootView: ToastView(content: content))
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 112)

        let panel = NSPanel(contentRect: hosting.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.contentView = hosting

        let target = anchor(for: panel.frame.size)
        panel.setFrameOrigin(CGPoint(x: target.x + 24, y: target.y))
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(target)
            panel.animator().alphaValue = 1
        }

        self.panel = panel

        let work = DispatchWorkItem { [weak self] in self?.dismiss(animated: true) }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4, execute: work)
    }

    public func dismiss(animated: Bool) {
        dismissal?.cancel()
        dismissal = nil
        guard let panel else { return }
        self.panel = nil

        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    private func anchor(for size: CGSize) -> CGPoint {
        let snapshot = DisplayRegistry.current
        let cursor = CGEvent(source: nil)?.location ?? .zero
        let display = snapshot.display(containing: cursor) ?? snapshot.displays.first
        guard let display else { return CGPoint(x: 40, y: 40) }
        let work = Geo.cocoa(fromAX: display.workAreaAX, flipY: snapshot.flipY)
        return CGPoint(x: work.maxX - size.width - 8, y: work.maxY - size.height + 2)
    }
}
