import AppKit

public enum WindowInventory {
    public static let protectedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.tobykalkman.snappy",
    ]

    public static func manageableApplications() -> [NSRunningApplication] {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular, !app.isTerminated else { return false }
            guard app.processIdentifier != ourPID else { return false }
            guard let bundleID = app.bundleIdentifier else { return true }
            return !protectedBundleIDs.contains(bundleID)
        }
    }

    public static func windowCount(of applications: [NSRunningApplication]) -> Int {
        applications.reduce(0) { total, app in
            total + WindowPlacer.standardWindows(of: AX.application(pid: app.processIdentifier)).count
        }
    }

    public static func windows(ofBundleID bundleID: String) -> Set<AXElement> {
        var result: Set<AXElement> = []
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where !app.isTerminated {
            for window in WindowPlacer.standardWindows(of: AX.application(pid: app.processIdentifier)) {
                result.insert(window)
            }
        }
        return result
    }

    public static func windows(ofPID pid: pid_t) -> [AXElement] {
        WindowPlacer.standardWindows(of: AX.application(pid: pid))
    }

    @discardableResult
    public static func closeAll(_ applications: [NSRunningApplication]) -> Int {
        var closed = 0
        for app in applications where app.terminate() { closed += 1 }
        return closed
    }

    @discardableResult
    public static func forceQuitAll(_ applications: [NSRunningApplication]) -> Int {
        var killed = 0
        for app in applications where app.forceTerminate() { killed += 1 }
        return killed
    }
}
