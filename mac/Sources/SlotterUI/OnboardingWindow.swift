import AppKit
import SlotterKit
import SwiftUI

private let P = T.palette

public struct OnboardingView: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    public init(onOpenSettings: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                if let icon = Mark.appIcon {
                    Image(nsImage: icon).resizable().frame(width: 56, height: 56)
                } else {
                    Glyph(size: 32).foregroundStyle(P.ink)
                        .frame(width: 56, height: 56)
                        .background(RoundedRectangle(cornerRadius: 12).fill(P.desk))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Slotter needs Accessibility access")
                        .font(T.font(T.type.heading + 2, .display))
                        .tracking(-0.3)
                        .foregroundStyle(P.ink)
                    Text("It is the only permission Slotter asks for.")
                        .font(T.font(T.type.body))
                        .foregroundStyle(P.ink2)
                }
            }
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 10) {
                point("macOS only lets an app move another app's windows through the Accessibility API. "
                    + "Without it Slotter runs, but every snap does nothing.")
                point("Open System Settings takes you to Privacy & Security, Accessibility, "
                    + "where you switch Slotter on. Nothing else is touched.")
                point("Slotter never reads window contents or keystrokes. It reads window positions "
                    + "and sets new ones.")
            }

            Spacer(minLength: 18)

            Rectangle().fill(P.rule).frame(height: 1).padding(.horizontal, -26)
            HStack(spacing: 8) {
                StatusLine()
                Spacer()
                Button("Not now", action: onDismiss).buttonStyle(InkButtonStyle(kind: .quiet))
                Button("Open System Settings", action: onOpenSettings)
                    .buttonStyle(InkButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 26)
        .padding(.top, 40)
        .padding(.bottom, 14)
        .frame(width: 540, height: 360, alignment: .topLeading)
        .background(P.ground)
        .environment(\.colorScheme, .dark)
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(P.ink3).frame(width: 5, height: 5).padding(.top, 6)
            Text(text)
                .font(T.font(T.type.body))
                .foregroundStyle(P.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct StatusLine: View {
        var body: some View {
            HStack(spacing: 5) {
                Icon(kind: .warn, size: 12)
                Text("Not granted").font(T.font(T.type.small, .semibold))
            }
            .foregroundStyle(P.error)
        }
    }
}

@MainActor
public enum OnboardingWindow {
    private static var window: NSWindow?

    public static func present() {
        guard window == nil else {
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 360),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered,
                             defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = T.palette.ground.ns
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: OnboardingView(
            onOpenSettings: {
                AX.requestTrust()
                AX.openAccessibilitySettings()
                dismiss()
            },
            onDismiss: { dismiss() }))
        panel.center()

        window = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    public static func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}
