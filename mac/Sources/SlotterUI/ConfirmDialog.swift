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
            HStack(alignment: .top, spacing: 12) {
                if request.danger {
                    Icon(kind: .warn, size: 18).foregroundStyle(T.palette.error).padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(request.heading)
                        .font(T.font(T.type.heading, .extraBold))
                        .foregroundStyle(T.palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(request.body)
                        .font(T.font(T.type.body))
                        .foregroundStyle(T.palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Rectangle().fill(T.palette.rule).frame(height: 1)

            HStack(spacing: 8) {
                Spacer()
                Button(request.cancelTitle, action: onCancel)
                    .buttonStyle(InkButtonStyle(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
                Button(request.confirmTitle, action: onConfirm)
                    .buttonStyle(InkButtonStyle(kind: request.danger ? .danger : .primary))
                    .keyboardShortcut(request.danger ? KeyboardShortcut("\r", modifiers: .command) : .defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
        .frame(width: 440)
        .background(T.palette.sheet)
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
        panel.backgroundColor = T.palette.sheet.ns
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
