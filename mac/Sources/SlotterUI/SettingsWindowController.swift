import AppKit
import SlotterKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSObject {
    public static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var model: SettingsModel?
    private var spaceRefreshTimer: Timer?

    public var canUndoLayout: Bool { model?.canUndoLayout ?? false }
    public var canRedoLayout: Bool { model?.canRedoLayout ?? false }
    public func undoLayout() { model?.undoLayout() }
    public func redoLayout() { model?.redoLayout() }
    public func flushBeforeTermination() { model?.flushOnClose() }

    public func show(config: SlotterConfig, status: SettingsModel.Status, openPrograms: Bool = false,
                     actions: SettingsModel.Actions) {
        if let window, let model {
            model.snapshot = DisplayRegistry.current
            model.remembered = MonitorMemory.load()
            model.status = status
            model.actions = actions
            if openPrograms { model.showingPrograms = true }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let model = SettingsModel(config: config, snapshot: DisplayRegistry.current, status: status, actions: actions)
        model.showingPrograms = openPrograms
        self.model = model

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 772),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "Slotter"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = T.palette.ground.ns
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: DesignerView(model: model))
        window.setFrame(NSRect(x: 0, y: 0, width: 1180, height: 800), display: false)
        window.minSize = NSSize(width: 640, height: 600)
        window.center()

        self.window = window
        spaceRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSpaces() }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Keeps the settings face honest while the window is open.
    public func update(status: SettingsModel.Status) {
        model?.status = status
    }

    public func displaysChanged() {
        model?.snapshot = DisplayRegistry.current
        model?.remembered = MonitorMemory.load()
    }

    private func requestClose() {
        model?.flushOnClose()
        close()
    }

    private func close() {
        spaceRefreshTimer?.invalidate()
        spaceRefreshTimer = nil
        window?.orderOut(nil)
        window = nil
        model = nil
    }

    private func refreshSpaces() {
        guard let model else { return }
        let snapshot = SpaceRegistry.shared.snapshot()
        if model.status.spaceSnapshot != snapshot { model.status.spaceSnapshot = snapshot }
    }
}

extension SettingsWindowController: NSWindowDelegate {
    public func windowDidBecomeKey(_ notification: Notification) {
        refreshSpaces()
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestClose()
        return false
    }
}
