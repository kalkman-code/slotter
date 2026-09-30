import AppKit
import SnappyKit

@MainActor
public final class StatusMenuController: NSObject {
    public struct Callbacks {
        public var launch: (Workspace) -> Void
        public var clearActiveZones: () -> Void
        public var openSettings: () -> Void
        public var openPrograms: () -> Void
        public var reloadConfig: () -> Void
        public var setLoginItem: (Bool) -> Void
        public var openLoginSettings: () -> Void
        public var closeAll: () -> Void
        public var forceQuitAll: () -> Void
        public var grantAccessibility: () -> Void
        public var quit: () -> Void

        public init(launch: @escaping (Workspace) -> Void,
                    clearActiveZones: @escaping () -> Void,
                    openSettings: @escaping () -> Void,
                    openPrograms: @escaping () -> Void,
                    reloadConfig: @escaping () -> Void,
                    setLoginItem: @escaping (Bool) -> Void,
                    openLoginSettings: @escaping () -> Void,
                    closeAll: @escaping () -> Void,
                    forceQuitAll: @escaping () -> Void,
                    grantAccessibility: @escaping () -> Void,
                    quit: @escaping () -> Void) {
            self.launch = launch
            self.clearActiveZones = clearActiveZones
            self.openSettings = openSettings
            self.openPrograms = openPrograms
            self.reloadConfig = reloadConfig
            self.setLoginItem = setLoginItem
            self.openLoginSettings = openLoginSettings
            self.closeAll = closeAll
            self.forceQuitAll = forceQuitAll
            self.grantAccessibility = grantAccessibility
            self.quit = quit
        }
    }

    public var config = SnappyConfig()
    public var activeWorkspace = ""
    public var shortcutRegistrations: [ShortcutCenter.Registration] = []

    private let callbacks: Callbacks
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var workspaceItems: [ObjectIdentifier: Workspace] = [:]

    public init(callbacks: Callbacks) {
        self.callbacks = callbacks
        super.init()
    }

    public func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Mark.statusItemImage()
        item.button?.toolTip = "Snappy — workspace launcher"
        let menu = NSMenu()
        menu.delegate = self
        // Left click opens the app, right click opens this menu -- the house rule across every
        // Y-family menu bar item. An NSStatusItem with `menu` set hands it every click, so the
        // menu is attached only for the moment a right click needs it.
        self.menu = menu
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let rightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        guard rightClick, let item = statusItem, let menu else {
            callbacks.openSettings()
            return
        }
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func launchWorkspace(_ sender: NSMenuItem) {
        guard let workspace = workspaceItems[ObjectIdentifier(sender)] else { return }
        callbacks.launch(workspace)
    }

    @objc private func clearActiveZones() { callbacks.clearActiveZones() }
    @objc private func openSettings() { callbacks.openSettings() }
    @objc private func openPrograms() { callbacks.openPrograms() }
    @objc private func reloadConfig() { callbacks.reloadConfig() }
    @objc private func grantAccessibility() { callbacks.grantAccessibility() }
    @objc private func closeAll() { callbacks.closeAll() }
    @objc private func forceQuitAll() { callbacks.forceQuitAll() }
    @objc private func quit() { callbacks.quit() }

    @objc private func toggleLoginItem() {
        switch LoginItem.state {
        case .requiresApproval: callbacks.openLoginSettings()
        case .enabled: callbacks.setLoginItem(false)
        default: callbacks.setLoginItem(true)
        }
    }
}

extension StatusMenuController: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        workspaceItems.removeAll()

        let title = NSMenuItem(title: "Snappy 1.0", action: nil, keyEquivalent: "")
        title.attributedTitle = NSAttributedString(string: "Snappy 1.0", attributes: [
            .font: Theme.font(Theme.Size.body, .semibold),
            .foregroundColor: Theme.accent,
        ])
        title.image = Sym.image("workspace", tint: Theme.accent, points: 13)
        title.isEnabled = false
        menu.addItem(title)

        if !AX.isTrusted {
            menu.addItem(.separator())
            let warning = NSMenuItem(title: "Accessibility not granted",
                                     action: #selector(grantAccessibility), keyEquivalent: "")
            warning.attributedTitle = NSAttributedString(string: "Grant Accessibility…", attributes: [
                .font: Theme.font(Theme.Size.body, .medium),
                .foregroundColor: Theme.danger,
            ])
            warning.image = Sym.image("kill", tint: Theme.danger, points: 13)
            warning.target = self
            menu.addItem(warning)
            let explain = NSMenuItem(title: "Snappy cannot move windows until you allow it.",
                                     action: nil, keyEquivalent: "")
            explain.isEnabled = false
            menu.addItem(explain)
        }

        menu.addItem(.separator())

        if config.workspaces.isEmpty {
            let empty = NSMenuItem(title: "No workspaces yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for workspace in config.workspaces {
                let item = NSMenuItem(title: workspace.name, action: #selector(launchWorkspace(_:)), keyEquivalent: "")
                item.target = self
                let isActive = workspace.name.caseInsensitiveCompare(activeWorkspace) == .orderedSame
                if isActive {
                    item.attributedTitle = NSAttributedString(string: workspace.name, attributes: [
                        .font: Theme.font(Theme.Size.body, .semibold),
                        .foregroundColor: Theme.accent,
                    ])
                }
                item.image = Sym.image(isActive ? "set" : "workspace",
                                       tint: isActive ? Theme.accent : Theme.dim, points: 13)
                let count = workspace.zones.count
                item.toolTip = count == 1 ? "1 zone" : "\(count) zones"
                workspaceItems[ObjectIdentifier(item)] = workspace
                menu.addItem(item)
            }

            if !activeWorkspace.isEmpty {
                // Checkable rather than a plain command: it is live state ("this workspace's
                // zones are the current drag targets"), not a one-shot action, even though only
                // switching it off is wired here — turning zone-snapping on without launching a
                // workspace's apps has no equivalent today, so the item is deliberately shown on
                // rather than a genuine two-way switch.
                let stop = NSMenuItem(title: "\(activeWorkspace) zones are active",
                                      action: #selector(clearActiveZones), keyEquivalent: "")
                stop.image = Sym.image("zone", tint: Theme.live, points: 13)
                stop.state = .on
                stop.toolTip = "Click to stop — dragging then falls back to edge and corner snapping only."
                stop.target = self
                menu.addItem(stop)
            }
        }

        menu.addItem(.separator())

        let programs = NSMenuItem(title: "Programs…", action: #selector(openPrograms), keyEquivalent: "")
        programs.image = Sym.image("program", tint: Theme.dim, points: 13)
        programs.target = self
        menu.addItem(programs)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.image = Sym.image("settings", tint: Theme.dim, points: 13)
        settings.target = self
        menu.addItem(settings)

        let reload = NSMenuItem(title: "Reload configuration", action: #selector(reloadConfig), keyEquivalent: "")
        reload.image = Sym.image("reload", tint: Theme.dim, points: 13)
        reload.toolTip = "Re-reads profiles.ini from disk. Snappy also watches it live."
        reload.target = self
        menu.addItem(reload)

        let login = NSMenuItem(title: loginTitle, action: #selector(toggleLoginItem), keyEquivalent: "")
        login.image = Sym.image("startup", tint: Theme.dim, points: 13)
        login.state = LoginItem.state.isOn ? .on : .off
        login.target = self
        if LoginItem.state == .unavailable { login.isEnabled = false }
        menu.addItem(login)

        let controls = NSMenu()
        let close = NSMenuItem(title: "Close every open app", action: #selector(closeAll), keyEquivalent: "")
        close.image = Sym.image("close", tint: Theme.dim, points: 13)
        close.target = self
        controls.addItem(close)

        let force = NSMenuItem(title: "Force close every open app…", action: #selector(forceQuitAll), keyEquivalent: "")
        force.attributedTitle = NSAttributedString(string: "Force close every open app…", attributes: [
            .font: Theme.font(Theme.Size.body),
            .foregroundColor: Theme.danger,
        ])
        force.image = Sym.image("kill", tint: Theme.danger, points: 13)
        force.target = self
        controls.addItem(force)

        let controlsItem = NSMenuItem(title: "Window controls", action: nil, keyEquivalent: "")
        controlsItem.image = Sym.image("windows", tint: Theme.dim, points: 13)
        controlsItem.submenu = controls
        menu.addItem(controlsItem)

        if AX.isTrusted { menu.addItem(shortcutsItem()) }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Snappy", action: #selector(quit), keyEquivalent: "q")
        quitItem.image = Sym.image("exit", tint: Theme.dim, points: 13)
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private var loginTitle: String {
        switch LoginItem.state {
        case .requiresApproval: return "Start at login — approve in System Settings…"
        case .unavailable: return "Start at login unavailable"
        default: return "Start at login"
        }
    }

    private func shortcutsItem() -> NSMenuItem {
        let submenu = NSMenu()
        for registration in shortcutRegistrations {
            let item = NSMenuItem(title: registration.title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            if !registration.succeeded {
                item.attributedTitle = NSAttributedString(string: registration.title, attributes: [
                    .font: Theme.font(Theme.Size.body),
                    .foregroundColor: Theme.danger,
                ])
            }
            submenu.addItem(item)
        }

        let failures = shortcutRegistrations.filter { !$0.succeeded }.count
        let item = NSMenuItem(
            title: failures == 0 ? "Snap shortcuts" : "Snap shortcuts — \(failures) unavailable",
            action: nil, keyEquivalent: "")
        item.image = Sym.image("hotkey", tint: failures == 0 ? Theme.dim : Theme.danger, points: 13)
        item.submenu = submenu
        return item
    }
}
