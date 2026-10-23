import AppKit
import SlotterKit
import SlotterUI

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private var menuController: StatusMenuController?
    private var dragService: DragSnapService?
    private var registrations: [ShortcutCenter.Registration] = []
    private var config = SlotterConfig()
    private var activeWorkspace: String?
    private var manualSelectionCleared = false
    private var currentSpaceSnapshot = SpaceSnapshot(available: false)
    private var resolvedWorkspacesByDisplay: [String: Workspace] = [:]
    private var loggedSpaceUUIDs: [String: String]?
    private var spaceRefreshGeneration = 0
    private var launchTask: Task<Void, Never>?
    private let openSettingsAtLaunch: Bool
    private let updates = UpdateController()

    @objc func checkForUpdates(_ sender: Any?) { updates.checkNow() }

    @objc func undoLayout(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
            text.undoManager?.undo()
        } else { SettingsWindowController.shared.undoLayout() }
    }

    @objc func redoLayout(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
            text.undoManager?.redo()
        } else { SettingsWindowController.shared.redoLayout() }
    }

    init(openSettings: Bool = false) {
        openSettingsAtLaunch = openSettings
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dark only: pin AppKit's own chrome (menus, alerts, standard controls) rather than
        // following the system appearance.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        Fonts.register()

        DisplayRegistry.refresh()

        ConfigStore.shared.writeDefaultIfMissing()
        config = ConfigStore.shared.load()
        activeWorkspace = config.workspace(named: config.lastWorkspace)?.name
        settleSpaceResolution()
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
            quit: { NSApp.terminate(nil) },
            checkForUpdates: { [weak self] in self?.updates.checkNow() }))
        controller.install()
        menuController = controller
        updates.onChange = { [weak self] in self?.refreshMenuState() }
        updates.start()

        SnapEngine.onFeedback = { title, body, success in
            ToastPresenter.shared.show(ToastContent(title: title, body: body, success: success))
        }
        ShortcutCenter.shared.onAction = { action in SnapEngine.perform(action) }
        ShortcutCenter.shared.onRegistrationsChanged = { [weak self] results in
            guard let self else { return }
            self.registrations = results
            self.refreshMenuState()
        }

        let drag = DragSnapService(callbacks: .init(
            present: { targets, flipY in OverlayCoordinator.shared.present(zones: targets, flipY: flipY) },
            reveal: { OverlayCoordinator.shared.reveal() },
            highlight: { target, flipY in OverlayCoordinator.shared.highlight(target, flipY: flipY) },
            dismiss: { OverlayCoordinator.shared.dismissAnimated() }))
        drag.workspaceProvider = { [weak self] in
            guard let self, let active = self.activeWorkspace else { return nil }
            return self.config.workspace(named: active)
        }
        drag.workspacesByDisplayProvider = { [weak self] in
            guard let self else { return [:] }
            self.refreshSpaceResolution()
            return self.resolvedWorkspacesByDisplay
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
            self, selector: #selector(spaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceDidChange),
            name: NSWorkspace.didWakeNotification, object: nil)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(cancelDrag),
            name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(accessibilityTrustChanged),
            name: NSNotification.Name("com.apple.accessibility.api"), object: nil)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(openSettingsRequested),
            name: openSettingsNotification, object: nil)

        Log.write("launched, bundle=\(bundleIdentifier), version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "unknown"), build=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "unknown"), trusted=\(AX.isTrusted)")
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
        cancelLaunch()
        SettingsWindowController.shared.flushBeforeTermination()
        dragService?.stop()
        ShortcutCenter.shared.unregisterAll()
        ConfigStore.shared.stopWatching()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func screenParametersChanged() {
        cancelLaunch()
        let snapshot = DisplayRegistry.refresh()
        settleSpaceResolution()
        FrameHistory.shared.clampToDisplays(snapshot)
        dragService?.cancel()
        SettingsWindowController.shared.displaysChanged()
        refreshMenuState()
        Log.write("display arrangement changed")
        logDisplays()
    }

    @objc private func cancelDrag() {
        dragService?.cancel()
    }

    @objc private func spaceDidChange() {
        cancelLaunch()
        dragService?.cancel()
        settleSpaceResolution()
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
        registrations = ShortcutCenter.shared.register(MagnetLayouts.table(overrides: config.shortcuts))
        if AX.isTrusted { dragService?.start() }
        else { dragService?.stop() }
    }

    private func reloadConfig() {
        config = ConfigStore.shared.load()
        if let activeWorkspace, config.workspace(named: activeWorkspace) == nil {
            self.activeWorkspace = config.workspace(named: config.lastWorkspace)?.name
        }
        applyShortcuts()
        refreshSpaceResolution()
        refreshMenuState()
        Log.write("config reloaded: \(config.workspaces.count) workspaces, \(config.programs.count) programs")
    }

    private func refreshMenuState() {
        menuController?.config = config
        menuController?.activeWorkspace = activeWorkspace ?? ""
        menuController?.shortcutRegistrations = registrations
        menuController?.canCheckForUpdates = updates.canCheck
        SettingsWindowController.shared.update(status: designerStatus)
    }

    private var designerStatus: SettingsModel.Status {
        SettingsModel.Status(accessibilityTrusted: AX.isTrusted,
                             shortcutCount: registrations.count,
                             shortcutFailures: registrations.filter { !$0.succeeded }.count,
                             loginNeedsApproval: LoginItem.state == .requiresApproval,
                             unavailableShortcuts: registrations.filter { !$0.succeeded }.map { $0.action.rawValue },
                             spaceSnapshot: currentSpaceSnapshot,
                             automaticUpdates: updates.automaticallyChecks,
                             canCheckForUpdates: updates.canCheck)
    }

    private func refreshSpaceResolution() {
        let manual = config.workspace(named: activeWorkspace ?? config.lastWorkspace)
        let result = VirtualPlateResolver().resolve(manualWorkspace: manual, workspaces: config.workspaces)
        var changed = false
        for index in config.workspaces.indices {
            if config.workspaces[index].reconcileDesktops(result.snapshot) { changed = true }
        }
        if changed { ConfigStore.shared.save(config) }
        currentSpaceSnapshot = result.snapshot
        resolvedWorkspacesByDisplay = result.workspacesByDisplay
    }

    private func settleSpaceResolution() {
        spaceRefreshGeneration += 1
        let generation = spaceRefreshGeneration
        refreshSpaceResolution()
        logDesktopChanges(in: currentSpaceSnapshot)
        for delay in [0.2, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.spaceRefreshGeneration == generation else { return }
                self.refreshSpaceResolution()
                self.logDesktopChanges(in: self.currentSpaceSnapshot)
                self.refreshMenuState()
            }
        }
        refreshMenuState()
    }

    private func logDesktopChanges(in current: SpaceSnapshot) {
        guard current.available else { return }
        let previous = loggedSpaceUUIDs
        loggedSpaceUUIDs = Dictionary(uniqueKeysWithValues: current.displays.compactMap { display in
            display.currentSpace.map { (display.displayUUID, $0.uuid) }
        })
        guard let previous else { return }
        let manual = manualSelectionCleared ? nil
            : config.workspace(named: activeWorkspace ?? config.lastWorkspace)
        for display in current.displays {
            guard let space = display.currentSpace,
                  let old = previous[display.displayUUID], old != space.uuid else { continue }
            let plate = manual.flatMap { workspace in
                workspace.virtualPlates.first(where: { plate in
                    let uuid = DisplayRegistry.resolve(plate.monitor)?.uuid ?? plate.monitor.uuid
                    return !space.isFullscreen && plate.desktopID == space.uuid
                        && uuid?.caseInsensitiveCompare(display.displayUUID) == .orderedSame
                })
                    .map { (workspace, $0) }
            }
            if let (workspace, plate) = plate {
                Log.write("desktop changed: \(space.label) on \(display.displayName) uuid=\(space.uuid); virtual plate \(plate.name) in \(workspace.name)")
            } else {
                Log.write("desktop changed: \(space.label) on \(display.displayName) uuid=\(space.uuid); physical plate -> manual \(manual?.name ?? "none")")
            }
        }
    }

    private func clearActiveZones() {
        cancelLaunch()
        guard let name = activeWorkspace else { return }
        activeWorkspace = nil
        manualSelectionCleared = true
        settleSpaceResolution()
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
            toast("Accessibility not granted", "Slotter cannot place windows until you allow it.", success: false)
            grantAccessibility()
            return
        }
        guard !WorkspaceLauncher.shared.isLaunching else {
            toast("A workspace is already launching", "Wait for the current apps to finish opening.", success: false)
            return
        }

        config.lastWorkspace = workspace.name
        activeWorkspace = workspace.name
        manualSelectionCleared = false
        ConfigStore.shared.save(config)
        refreshSpaceResolution()
        refreshMenuState()

        let plan = VirtualPlateResolver().workspaceForLaunch(workspace)
        let assigned = plan.zones.filter { !($0.program ?? "").isEmpty }.count
        if plan.zones.isEmpty {
            toast("\(workspace.name) has no zones", "Open Settings and choose a layout preset.", success: false)
            return
        }
        if assigned == 0 {
            toast("\(workspace.name) is ready",
                  "\(plan.zones.count) manual snap zones are active.", success: true)
            return
        }

        toast("Launching \(workspace.name)", "Opening and placing \(assigned) apps…", success: true)

        launchTask = Task {
            guard let result = await WorkspaceLauncher.shared.activate(plan, programs: config.programs) else { return }
            if result.cancelled {
                toast("Launch stopped", "The desktop or display changed. Launch the workspace again on this desktop.", success: false)
                return
            }
            let placed = "\(result.placed) of \(result.planned) apps placed."
            if result.placed == result.planned && result.firstError == nil {
                toast("\(workspace.name) launched.", placed, success: true)
            } else {
                ToastPresenter.shared.show(ToastContent(title: "\(workspace.name) launched.", body: placed, success: false,
                                                        problem: result.firstError ?? ""))
            }
        }
    }

    private func cancelLaunch() {
        launchTask?.cancel()
        WorkspaceLauncher.shared.cancel()
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
        refreshSpaceResolution()
        NSApp.activate()
        let actions = SettingsModel.Actions(
            save: { [weak self] updated in self?.store(updated) },
            setWorkspace: { [weak self] workspace in self?.launch(workspace) },
            openAccessibilitySettings: {
                AX.requestTrust()
                AX.openAccessibilitySettings()
            },
            openLoginItemsSettings: { LoginItem.openLoginItemsSettings() },
            setAutomaticUpdates: { [weak self] in self?.updates.automaticallyChecks = $0 },
            checkForUpdates: { [weak self] in self?.updates.checkNow() })
        SettingsWindowController.shared.show(config: config, status: designerStatus,
                                             openPrograms: openPrograms, actions: actions)
    }

    /// Persists what the designer saved and returns it as stored, since macOS may refuse the
    /// start-at-login change.
    private func store(_ updated: SlotterConfig) -> SlotterConfig? {
        var saved = updated
        if updated.startAtLogin != LoginItem.state.isOn {
            if !LoginItem.set(updated.startAtLogin) {
                toast("Start at login failed",
                      "macOS refused the change. Check Login Items in System Settings.",
                      success: false)
            }
            saved.startAtLogin = LoginItem.state.isOn
        }
        guard ConfigStore.shared.save(saved) else {
            toast("Settings could not be written", "Slotter could not update profiles.ini.", success: false)
            return nil
        }
        if let active = activeWorkspace, saved.workspace(named: active) == nil {
            activeWorkspace = saved.workspace(named: saved.lastWorkspace)?.name
        }
        config = saved
        settleSpaceResolution()
        applyShortcuts()
        refreshMenuState()
        return saved
    }
}

extension AppController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates(_:)) { return updates.canCheck }
        if menuItem.action == #selector(undoLayout(_:)) {
            if let text = NSApp.keyWindow?.firstResponder as? NSTextView { return text.undoManager?.canUndo ?? false }
            return SettingsWindowController.shared.canUndoLayout
        }
        if menuItem.action == #selector(redoLayout(_:)) {
            if let text = NSApp.keyWindow?.firstResponder as? NSTextView { return text.undoManager?.canRedo ?? false }
            return SettingsWindowController.shared.canRedoLayout
        }
        return true
    }
}
