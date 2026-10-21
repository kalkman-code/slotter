import AppKit
import SlotterKit

let bundleIdentifier = Bundle.main.bundleIdentifier ?? "uk.co.kalkman.slotter"
let openSettingsNotification = Notification.Name("uk.co.kalkman.slotter.openSettings")
let wantsSettings = CommandLine.arguments.contains("--settings")

let ourPID = ProcessInfo.processInfo.processIdentifier
let alreadyRunning = NSRunningApplication
    .runningApplications(withBundleIdentifier: bundleIdentifier)
    .contains { $0.processIdentifier != ourPID }

if alreadyRunning {
    if wantsSettings {
        DistributedNotificationCenter.default().postNotificationName(
            openSettingsNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }
    Log.write("another instance is already running — exiting")
    exit(0)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

// An .accessory app draws no menu bar, but the main menu still supplies key
// equivalents to the key window — without it Cmd-W and Cmd-Q do nothing.
let mainMenu = NSMenu()
let appItem = NSMenuItem()
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Quit Slotter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appItem.submenu = appMenu
mainMenu.addItem(appItem)
let windowItem = NSMenuItem()
let windowMenu = NSMenu(title: "Window")
windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
windowMenu.addItem(withTitle: "Minimise", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
windowItem.submenu = windowMenu
mainMenu.addItem(windowItem)
application.mainMenu = mainMenu

let controller = AppController(openSettings: wantsSettings)
let editItem = NSMenuItem()
let editMenu = NSMenu(title: "Edit")
let undoItem = editMenu.addItem(withTitle: "Undo", action: #selector(AppController.undoLayout(_:)), keyEquivalent: "z")
undoItem.target = controller
let redoItem = editMenu.addItem(withTitle: "Redo", action: #selector(AppController.redoLayout(_:)), keyEquivalent: "z")
redoItem.target = controller
redoItem.keyEquivalentModifierMask = [.command, .shift]
editMenu.addItem(.separator())
editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editItem.submenu = editMenu
mainMenu.insertItem(editItem, at: 1)
application.delegate = controller
application.run()
