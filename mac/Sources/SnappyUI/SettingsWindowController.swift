import AppKit
import SnappyKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSObject {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var model: SettingsModel?
    private var commit: ((SnappyConfig) -> Void)?

    public func show(config: SnappyConfig, openPrograms: Bool = false, onSave: @escaping (SnappyConfig) -> Void) {
        if let window, let model {
            model.selectedDisplayID = DisplayRegistry.current.displays.first?.id
            commit = onSave
            if openPrograms, let hosting = window.contentView as? NSHostingView<SettingsView> {
                hosting.rootView = SettingsView(model: model,
                                                onSave: { [weak self] in self?.save() },
                                                onCancel: { [weak self] in self?.requestClose() },
                                                openPrograms: true)
            }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let model = SettingsModel(config: config)
        self.model = model
        commit = onSave

        let view = SettingsView(model: model,
                                onSave: { [weak self] in self?.save() },
                                onCancel: { [weak self] in self?.requestClose() },
                                openPrograms: openPrograms)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.title = "Snappy Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Theme.bg
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: view)
        window.center()

        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func save() {
        guard let model else { return }
        commit?(model.config)
        close()
    }

    private func requestClose() {
        guard let model, model.dirty else {
            close()
            return
        }
        guard model.pendingConfirm == nil else { return }
        model.confirm(ConfirmRequest(
            heading: "Discard your changes?",
            body: "This workspace layout has unsaved edits.",
            confirmTitle: "Discard changes",
            danger: true)) { [weak self] in
            self?.close()
        }
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
        model = nil
        commit = nil
    }
}

extension SettingsWindowController: NSWindowDelegate {
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestClose()
        return false
    }
}
