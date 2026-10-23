import AppKit
import SlotterKit

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
        public var checkForUpdates: () -> Void

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
                    quit: @escaping () -> Void,
                    checkForUpdates: @escaping () -> Void = {}) {
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
            self.checkForUpdates = checkForUpdates
        }
    }

    public var config = SlotterConfig()
    public var activeWorkspace = ""
    public var shortcutRegistrations: [ShortcutCenter.Registration] = []
    public var canCheckForUpdates = false

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
        item.button?.toolTip = "Slotter"
        let menu = NSMenu()
        menu.delegate = self
        // Left click opens the designer, right click opens this menu. An NSStatusItem with `menu` set hands it every click, so the
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
    @objc private func checkForUpdates() { callbacks.checkForUpdates() }

    @objc private func toggleLoginItem() {
        switch LoginItem.state {
        case .requiresApproval: callbacks.openLoginSettings()
        case .enabled: callbacks.setLoginItem(false)
        default: callbacks.setLoginItem(true)
        }
    }
}

extension StatusMenuController: NSMenuDelegate {
    /// A native menu, drawn by macOS, in the design's order. macOS highlights rows itself.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        workspaceItems.removeAll()

        let title = NSMenuItem(title: "Slotter 1.0", action: nil, keyEquivalent: "")
        title.attributedTitle = NSAttributedString(string: "Slotter 1.0", attributes: [.font: T.nsFont(14, .extraBold)])
        title.image = Mark.statusItemImage()
        title.isEnabled = false
        menu.addItem(title)

        if !AX.isTrusted {
            menu.addItem(.separator())
            let warning = NSMenuItem(title: "Grant Accessibility…", action: #selector(grantAccessibility), keyEquivalent: "")
            warning.target = self
            menu.addItem(warning)
            let explain = NSMenuItem(title: "Slotter cannot move other apps’ windows until you allow it.", action: nil, keyEquivalent: "")
            explain.isEnabled = false
            menu.addItem(explain)
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Launch a workspace"))

        if config.workspaces.isEmpty {
            let empty = NSMenuItem(title: "No workspaces yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let snapshot = DisplayRegistry.current
            let remembered = MonitorMemory.load()
            for workspace in config.workspaces {
                let item = NSMenuItem(title: workspace.name, action: #selector(launchWorkspace(_:)), keyEquivalent: "")
                item.target = self
                let offline = Self.offlineMonitors(workspace, snapshot)
                let apps = VirtualPlateResolver().workspaceForLaunch(workspace).zones.filter { !($0.program ?? "").isEmpty }.count
                if !workspace.zones.isEmpty && offline.count == Set(workspace.zones.map { DeskPlanner.key(for: $0.monitor, in: snapshot) }).count {
                    item.isEnabled = false
                    item.detail(Self.offlineNames(workspace, snapshot, remembered) + " offline")
                } else {
                    item.detail(apps == 1 ? "1 app" : "\(apps) apps")
                }
                if workspace.name.caseInsensitiveCompare(activeWorkspace) == .orderedSame { item.state = .on }
                workspaceItems[ObjectIdentifier(item)] = workspace
                menu.addItem(item)
            }

            if !activeWorkspace.isEmpty {
                let stop = NSMenuItem(title: "Stop using \(activeWorkspace) zones", action: #selector(clearActiveZones), keyEquivalent: "")
                stop.toolTip = "Dragging then falls back to edge and corner snapping only."
                stop.target = self
                menu.addItem(stop)
            }
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        updates.isEnabled = canCheckForUpdates
        menu.addItem(updates)

        let programs = NSMenuItem(title: "Programs…", action: #selector(openPrograms), keyEquivalent: "")
        programs.target = self
        menu.addItem(programs)

        let login = NSMenuItem(title: loginTitle, action: #selector(toggleLoginItem), keyEquivalent: "")
        login.state = LoginItem.state.isOn ? .on : .off
        login.target = self
        if LoginItem.state == .unavailable { login.isEnabled = false }
        menu.addItem(login)

        if !shortcutRegistrations.isEmpty { menu.addItem(shortcutsItem()) }

        let controls = NSMenu()
        let close = NSMenuItem(title: "Close every open app", action: #selector(closeAll), keyEquivalent: "")
        close.target = self
        controls.addItem(close)
        let force = NSMenuItem(title: "Force close every open app…", action: #selector(forceQuitAll), keyEquivalent: "")
        force.target = self
        controls.addItem(force)
        let controlsItem = NSMenuItem(title: "Window controls", action: nil, keyEquivalent: "")
        controlsItem.submenu = controls
        menu.addItem(controlsItem)

        let reload = NSMenuItem(title: "Reload configuration", action: #selector(reloadConfig), keyEquivalent: "")
        reload.toolTip = "Re-reads profiles.ini from disk. Slotter also watches it live."
        reload.target = self
        menu.addItem(reload)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Slotter", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private static func offlineMonitors(_ workspace: Workspace, _ snapshot: DisplaySnapshot) -> Set<String> {
        Set(workspace.zones.map { DeskPlanner.key(for: $0.monitor, in: snapshot) }.filter { $0.hasPrefix("offline:") })
    }

    /// Names the unplugged monitors as the designer does: from memory, else by position.
    private static func offlineNames(_ workspace: Workspace, _ snapshot: DisplaySnapshot,
                                     _ remembered: [String: RememberedMonitor]) -> String {
        var seen = Set<String>()
        var names: [String] = []
        for ref in workspace.zones.map(\.monitor) {
            let key = DeskPlanner.key(for: ref, in: snapshot)
            guard key.hasPrefix("offline:"), seen.insert(key).inserted else { continue }
            names.append(ref.uuid.flatMap { remembered[$0]?.name } ?? "Monitor \(ref.ordinal)")
        }
        return names.count <= 1 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    private var loginTitle: String {
        switch LoginItem.state {
        case .requiresApproval: return "Start at login, approve in System Settings…"
        case .unavailable: return "Start at login unavailable"
        default: return "Start at login"
        }
    }

    private func shortcutsItem() -> NSMenuItem {
        let submenu = NSMenu()
        for registration in shortcutRegistrations {
            let item = NSMenuItem(title: registration.title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
        }

        let failures = shortcutRegistrations.filter { !$0.succeeded }.count
        return NSMenuItem(
            title: failures == 0 ? "Snap shortcuts" : "Snap shortcuts, \(failures) unavailable",
            action: nil, keyEquivalent: "").withSubmenu(submenu)
    }
}

extension StatusMenuController: NSMenuItemValidation {
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates) { return canCheckForUpdates }
        return menuItem.isEnabled
    }
}

private extension NSMenuItem {
    func withSubmenu(_ menu: NSMenu) -> NSMenuItem {
        submenu = menu
        return self
    }
}

private extension NSMenuItem {
    /// The design puts the app count or the offline reason beside each workspace; macOS draws it
    /// as a subtitle where it can, and as a tooltip before 14.4.
    func detail(_ text: String) {
        if #available(macOS 14.4, *) { subtitle = text } else { toolTip = text }
    }
}
