import AppKit
import SnappyKit
import SwiftUI

struct OnboardingView: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: Mark.appIcon(side: 52))
                    .resizable()
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Snappy needs Accessibility access")
                        .font(.system(size: Theme.Size.title, weight: .semibold))
                        .foregroundStyle(Color(theme: Theme.text))
                    Text("It is the only permission Snappy asks for.")
                        .font(.system(size: Theme.Size.body))
                        .foregroundStyle(Color(theme: Theme.dim))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                bullet("macOS only lets an app move another app's windows through the Accessibility API. "
                    + "Without it Snappy runs, but every snap does nothing.")
                bullet("Opening System Settings takes you to Privacy & Security → Accessibility, "
                    + "where you switch Snappy on. Nothing else is touched.")
                bullet("Snappy never reads window contents or keystrokes — it reads window positions "
                    + "and sets new ones.")
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                SnappyButton(title: "Not now", action: onDismiss)
                SnappyButton(title: "Open System Settings", glyph: "settings", style: .primary,
                             action: onOpenSettings)
            }
        }
        .padding(26)
        .frame(width: 540, height: 340)
        .background(Color(theme: Theme.bg))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(Color(theme: Theme.accent))
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: Theme.Size.body))
                .foregroundStyle(Color(theme: Theme.text))
                .fixedSize(horizontal: false, vertical: true)
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

        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 340),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered,
                             defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = Theme.bg
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
