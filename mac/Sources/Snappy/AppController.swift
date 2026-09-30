import AppKit
import SnappyKit
import SnappyUI

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private var menuController: StatusMenuController?
    private var dragService: DragSnapService?
    private var registrations: [ShortcutCenter.Registration] = []
    private var config = SnappyConfig()
    private var activeWorkspace: String?
    private let openSettingsAtLaunch: Bool

    init(openSettings: Bool = false) {
        openSettingsAtLaunch = openSettings
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Desk is dark only — pin AppKit's own chrome (menus, alerts, standard controls)
        // rather than following the system appearance. See docs/desk-design-system.md section 3.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        DisplayRegistry.refresh()

        ConfigStore.shared.writeDefaultIfMissing()
        config = ConfigStore.shared.load()
        ConfigStore.shared.onExternalChange = { [weak self] in self?.reloadConfig() }
        ConfigStore.shared.startWatching()

        config.startAtLogin = LoginItem.reconcile(wanted: config.startAtLogin)

        let controller = StatusMenuController(callbacks: .init(
            launch: { [weak self] workspace in self?.launch(workspace) },
            clearActiveZones: { [weak self] in self?.clearActiveZones() },
            openSettings: { [weak self] in self?.openSettings() },
            openPrograms: { [weak self] in self?.openSettings(openPrograms: true) },
            reloadConfig: { [weak self] in self?.reloadConfig() },
            setLoginItem: { [weak self] enabled in self?.setLoginItem(enabled) },
            openLoginSettings: { LoginItem.openLoginItemsSettings() },
            closeAll: { [weak self] in self?.closeAll() },
            forceQuitAll: { [weak self] in self?.forceQuitAll() },
            grantAccessibility: { [weak self] in self?.grantAccessibility() },
            quit: { NSApp.terminate(nil) }))
        controller.install()
        menuController = controller

        SnapEngine.onFeedback = { title, body, success in
            ToastPresenter.shared.show(ToastContent(title: title, body: body, success: success))
        }
        ShortcutCenter.shared.onAction = { action in SnapEngine.perform(action) }

        let drag = DragSnapService(callbacks: .init(
            present: { targets, flipY in OverlayCoordinator.shared.present(zones: targets, flipY: flipY) },
            reveal: { OverlayCoordinator.shared.reveal() },
            highlight: { target, flipY in OverlayCoordinator.shared.highlight(target, flipY: flipY) },
            dismiss: { OverlayCoordinator.shared.dismissAnimated() }))
        drag.workspaceProvider = { [weak self] in
            guard let self, let active = self.activeWorkspace else { return nil }
            return self.config.workspace(named: active)
        }
        dragService = drag

        applyShortcuts()
        refreshMenuState()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(applicationTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(cancelDrag),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(cancelDrag),
            name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(accessibilityTrustChanged),
            name: NSNotification.Name("com.apple.accessibility.api"), object: nil)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(openSettingsRequested),
            name: openSettingsNotification, object: nil)

        Log.write("launched, bundle=\(bundleIdentifier), trusted=\(AX.isTrusted)")
        Log.write("config: \(config.workspaces.count) workspaces, \(config.programs.count) programs, "
            + "last=\(config.lastWorkspace)")
        logDisplays()

        if !AX.isTrusted { grantAccessibility() }
        if openSettingsAtLaunch { openSettings() }
    }

    @objc private func openSettingsRequested() {
        DispatchQueue.main.async { self.openSettings() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dragService?.stop()
        ShortcutCenter.shared.unregisterAll()
        ConfigStore.shared.stopWatching()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func screenParametersChanged() {
        let snapshot = DisplayRegistry.refresh()
        FrameHistory.shared.clampToDisplays(snapshot)
        dragService?.cancel()
        Log.write("display arrangement changed")
        logDisplays()
    }

    @objc private func cancelDrag() {
        dragService?.cancel()
    }

    @objc private func applicationTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication else { return }
        FrameHistory.shared.purge(pid: app.processIdentifier)
    }

    @objc private func accessibilityTrustChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Log.write("accessibility trust changed, trusted=\(AX.isTrusted)")
            if AX.isTrusted { OnboardingWindow.dismiss() }
            self.applyShortcuts()
            self.refreshMenuState()
        }
    }

    private func grantAccessibility() {
        guard !AX.isTrusted else { return }
        OnboardingWindow.present()
    }

    private func applyShortcuts() {
        guard AX.isTrusted else {
            ShortcutCenter.shared.unregisterAll()
            dragService?.stop()
            registrations = []
            return
        }
        registrations = ShortcutCenter.shared.register(MagnetLayouts.table(overrides: config.shortcuts))
        dragService?.start()
    }

    private func reloadConfig() {
        config = ConfigStore.shared.load()
        applyShortcuts()
        refreshMenuState()
        Log.write("config reloaded: \(config.workspaces.count) workspaces, \(config.programs.count) programs")
    }

    private func refreshMenuState() {
        menuController?.config = config
        menuController?.activeWorkspace = activeWorkspace ?? ""
        menuController?.shortcutRegistrations = registrations
    }

    private func clearActiveZones() {
        guard let name = activeWorkspace else { return }
        activeWorkspace = nil
        refreshMenuState()
        toast("\(name) zones are off", "Dragging now snaps to screen edges and corners only.", success: true)
    }

    private func logDisplays() {
        let snapshot = DisplayRegistry.current
        Log.write("displays flipY=\(Int(snapshot.flipY)) count=\(snapshot.displays.count)")
        for display in snapshot.displays {
            Log.write("  \(display.name) pts=\(display.legacyKeyPoints) px=\(display.legacyKeyPixels) "
                + "frame=\(Geo.describe(display.frameAX)) work=\(Geo.describe(display.workAreaAX)) uuid=\(display.uuid)")
        }
    }

    private func toast(_ title: String, _ body: String, success: Bool) {
        ToastPresenter.shared.show(ToastContent(title: title, body: body, success: success))
    }

    private func launch(_ workspace: Workspace) {
        guard AX.isTrusted else {
            toast("Accessibility not granted", "Snappy cannot place windows until you allow it.", success: false)
            grantAccessibility()
            return
        }
        guard !WorkspaceLauncher.shared.isLaunching else {
            toast("A workspace is already launching", "Wait for the current apps to finish opening.", success: false)
            return
        }

        config.lastWorkspace = workspace.name
        activeWorkspace = workspace.name
        ConfigStore.shared.save(config)
        refreshMenuState()

        let assigned = workspace.zones.filter { !($0.program ?? "").isEmpty }.count
        if workspace.zones.isEmpty {
            toast("\(workspace.name) has no zones", "Open Settings and choose a layout preset.", success: false)
            return
        }
        if assigned == 0 {
            toast("\(workspace.name) is ready",
                  "\(workspace.zones.count) manual snap zones are active.", success: true)
            return
        }

        toast("Launching \(workspace.name)", "Opening and placing \(assigned) apps…", success: true)

        Task {
            guard let result = await WorkspaceLauncher.shared.activate(workspace, programs: config.programs) else { return }
            if result.placed == result.planned && result.firstError == nil {
                toast("\(workspace.name) is ready",
                      result.placed == 1 ? "1 app snapped into place." : "\(result.placed) apps snapped into place.",
                      success: true)
            } else {
                toast("\(workspace.name) launched with issues",
                      "\(result.placed) of \(result.planned) apps were placed. \(result.firstError ?? "")",
                      success: false)
            }
        }
    }

    private func setLoginItem(_ enabled: Bool) {
        guard LoginItem.set(enabled) else {
            toast("Start at login failed", "macOS refused the change. Check Login Items in System Settings.",
                  success: false)
            return
        }
        config.startAtLogin = LoginItem.state.isOn
        ConfigStore.shared.save(config)
        refreshMenuState()
    }

    private func closeAll() {
        let apps = WindowInventory.manageableApplications()
        guard !apps.isEmpty else {
            toast("Nothing to close", "No other apps are open.", success: true)
            return
        }
        let closed = WindowInventory.closeAll(apps)
        toast("Asked \(closed) apps to close",
              "Any app with unsaved work will prompt you.", success: true)
    }

    private func forceQuitAll() {
        let apps = WindowInventory.manageableApplications()
        guard !apps.isEmpty else {
            toast("Nothing to force close", "No other apps are open.", success: true)
            return
        }

        ConfirmWindow.present(ConfirmRequest(
            heading: "Force close every open app?",
            body: "This immediately ends \(apps.count) running apps. Unsaved work can be lost.",
            confirmTitle: "Force close",
            danger: true)) { [weak self] confirmed in
            guard confirmed else { return }
            let killed = WindowInventory.forceQuitAll(apps)
            self?.toast("Force closed \(killed) apps", "Their processes were ended immediately.", success: false)
        }
    }

    private func openSettings(openPrograms: Bool = false) {
        NSApp.activate()
        SettingsWindowController.shared.show(config: config, openPrograms: openPrograms) { [weak self] updated in
            guard let self else { return }
            var saved = updated
            if updated.startAtLogin != LoginItem.state.isOn {
                if LoginItem.set(updated.startAtLogin) {
                    saved.startAtLogin = LoginItem.state.isOn
                } else {
                    saved.startAtLogin = LoginItem.state.isOn
                    self.toast("Start at login failed",
                               "macOS refused the change. Check Login Items in System Settings.",
                               success: false)
                }
            }
            if let active = self.activeWorkspace, saved.workspace(named: active) == nil {
                self.activeWorkspace = nil
            }
            self.config = saved
            ConfigStore.shared.save(saved)
            self.applyShortcuts()
            self.refreshMenuState()
        }
    }
}
