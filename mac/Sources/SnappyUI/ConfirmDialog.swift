import AppKit
import SwiftUI

public struct ConfirmRequest: Sendable, Equatable {
    public var heading: String
    public var body: String
    public var confirmTitle: String
    public var cancelTitle: String
    public var danger: Bool

    public init(heading: String,
                body: String,
                confirmTitle: String = "Continue",
                cancelTitle: String = "Cancel",
                danger: Bool = false) {
        self.heading = heading
        self.body = body
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.danger = danger
    }
}

@MainActor
public struct PendingConfirm: Identifiable {
    public let id = UUID()
    public let request: ConfirmRequest
    public let action: () -> Void

    public init(request: ConfirmRequest, action: @escaping () -> Void) {
        self.request = request
        self.action = action
    }
}

public struct ConfirmView: View {
    let request: ConfirmRequest
    let onConfirm: () -> Void
    let onCancel: () -> Void

    public init(request: ConfirmRequest,
                onConfirm: @escaping () -> Void,
                onCancel: @escaping () -> Void) {
        self.request = request
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: Sym.name(request.danger ? "kill" : "workspace"))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color(theme: request.danger ? Theme.danger : Theme.accent))
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 7) {
                    Text(request.heading)
                        .font(.system(size: Theme.Size.large, weight: .semibold))
                        .foregroundStyle(Color(theme: Theme.text))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(request.body)
                        .font(.system(size: Theme.Size.body))
                        .foregroundStyle(Color(theme: Theme.dim))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 22)

            Divider().overlay(Color(theme: Theme.rule))

            HStack(spacing: 10) {
                Spacer()
                SnappyButton(title: request.cancelTitle, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                SnappyButton(title: request.confirmTitle,
                             style: request.danger ? .danger : .primary,
                             action: onConfirm)
                    .keyboardShortcut(request.danger ? KeyboardShortcut("\r", modifiers: .command) : .defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
        }
        .frame(width: 440)
        .background(Color(theme: Theme.bg))
    }
}

@MainActor
public enum ConfirmWindow {
    private static var window: NSWindow?
    private static var completion: ((Bool) -> Void)?

    public static func present(_ request: ConfirmRequest, completion handler: @escaping (Bool) -> Void) {
        dismiss(false)
        completion = handler

        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 180),
                             styleMask: [.titled, .fullSizeContentView],
                             backing: .buffered,
                             defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.backgroundColor = Theme.bg
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: ConfirmView(
            request: request,
            onConfirm: { dismiss(true) },
            onCancel: { dismiss(false) }))
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        panel.center()

        window = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private static func dismiss(_ confirmed: Bool) {
        guard let panel = window else { return }
        window = nil
        panel.orderOut(nil)
        let handler = completion
        completion = nil
        handler?(confirmed)
    }
}
