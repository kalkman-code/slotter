import AppKit
import SnappyKit

let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.tobykalkman.snappy"
let openSettingsNotification = Notification.Name("com.tobykalkman.snappy.openSettings")
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
appMenu.addItem(withTitle: "Quit Snappy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
application.delegate = controller
application.run()
