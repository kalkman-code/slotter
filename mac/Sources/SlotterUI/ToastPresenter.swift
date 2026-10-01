import AppKit
import SlotterKit
import SwiftUI

private let P = T.palette

public struct ToastContent: Sendable, Equatable {
    public var title: String
    public var body: String
    public var success: Bool
    /// The reason a launch fell short. Only this clause takes the error colour.
    public var problem: String

    public init(title: String, body: String, success: Bool, problem: String = "") {
        self.title = title
        self.body = body
        self.success = success
        self.problem = problem
    }
}

public struct ToastView: View {
    let content: ToastContent

    public init(content: ToastContent) {
        self.content = content
    }

    private var message: Text {
        if !content.problem.isEmpty {
            return Text(content.body).foregroundColor(P.ink2) + Text(" " + content.problem).foregroundColor(P.error)
        }
        return Text(content.body).foregroundColor(content.success ? P.ink2 : P.error)
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Glyph(size: 18).foregroundStyle(P.ink)
                .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: T.radii.floating).fill(P.ground))

            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(T.font(T.type.tab, .bold))
                    .foregroundStyle(P.ink)
                    .lineLimit(1)
                message
                    .font(T.font(T.type.small))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 340, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: T.radii.floating).fill(P.floating))
        .overlay(RoundedRectangle(cornerRadius: T.radii.floating).strokeBorder(P.fieldBorder, lineWidth: 1))
        .floatingShadow()
        .padding(EdgeInsets(top: 6, leading: 20, bottom: 34, trailing: 20))
        .environment(\.colorScheme, .dark)
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
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

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

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.18
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
        return CGPoint(x: work.maxX - size.width + 12, y: work.maxY - size.height + 2)
    }
}
