import AppKit
import ApplicationServices

public enum AppLauncher {
    public enum LaunchError: LocalizedError, Sendable {
        case missingPath(String)
        case launchFailed(String, String)
        case noWindow(String)
        case noReusableWindow(String)
        case restoreFailed(String)

        public var errorDescription: String? {
            switch self {
            case .missingPath(let name): return "\(name): nothing exists at that path."
            case .launchFailed(let name, let reason): return "\(name): \(reason)"
            case .noWindow(let name): return "\(name): no window appeared in time."
            case .noReusableWindow(let name): return "\(name): no unused window was found on the current desktops. Enable Launch a new instance to open another copy."
            case .restoreFailed(let name): return "\(name): its window could not be restored."
            }
        }
    }

    public static func tokenise(_ arguments: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?

        for character in arguments {
            if let active = quote {
                if character == active { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    public static func launch(_ program: Program, excluding claimed: Set<AXElement> = [],
                              desktopSnapshot: SpaceSnapshot? = nil) async throws -> AXElement {
        try Task.checkCancellation()
        let path = program.path.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            throw LaunchError.missingPath(program.name)
        }

        let url = URL(fileURLWithPath: path)
        let arguments = tokenise(program.arguments)
        let desktops = desktopSnapshot ?? SpaceRegistry.shared.snapshot()

        if program.isAppBundle {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
                throw LaunchError.launchFailed(program.name, "not a readable application bundle.")
            }
            let before = await AX.perform { WindowInventory.windows(ofBundleID: bundleID) }
            try Task.checkCancellation()

            if arguments.isEmpty && !program.newInstance {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                } catch {
                    throw LaunchError.launchFailed(program.name, error.localizedDescription)
                }
            } else {
                var openArguments = ["-a", path]
                if program.newInstance { openArguments.insert("-n", at: 0) }
                if !arguments.isEmpty { openArguments.append("--args"); openArguments.append(contentsOf: arguments) }
                try run("/usr/bin/open", openArguments, program.name)
            }

            let window = try await waitForWindow(bundleID: bundleID, before: before, claimed: claimed,
                                                 reuse: !program.newInstance, preferNew: !arguments.isEmpty,
                                                 desktops: desktops, name: program.name)
            if let pid = AX.pid(of: window) {
                let restored = await MainActor.run { () -> Bool in
                    guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
                    if app.isHidden { _ = app.unhide() }
                    return true
                }
                guard restored else { throw LaunchError.restoreFailed(program.name) }
                for _ in 0..<20 {
                    try Task.checkCancellation()
                    if await MainActor.run(body: { NSRunningApplication(processIdentifier: pid)?.isHidden == false }) { return window }
                    try await Task.sleep(for: .milliseconds(50))
                }
                throw LaunchError.restoreFailed(program.name)
            }
            return window
        }

        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            throw LaunchError.launchFailed(program.name, error.localizedDescription)
        }
        return try await waitForNewWindow(pid: process.processIdentifier, name: program.name)
    }

    private static func run(_ tool: String, _ arguments: [String], _ name: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            throw LaunchError.launchFailed(name, error.localizedDescription)
        }
    }

    private static func waitForWindow(bundleID: String, before: Set<AXElement>, claimed: Set<AXElement>,
                                      reuse: Bool, preferNew: Bool, desktops: SpaceSnapshot,
                                      name: String) async throws -> AXElement {
        for attempt in 0..<50 {
            try Task.checkCancellation()
            let found = await AX.perform { () -> AXElement? in
                let windows = WindowInventory.windows(ofBundleID: bundleID).subtracting(claimed)
                let eligible = windows.filter { window in
                    desktops.available ? SpaceRegistry.shared.windowIsOnDesktop(window, expected: desktops) : !before.contains(window)
                }.sorted { left, right in
                    func rank(_ window: AXElement) -> (Int, Int, UInt32) {
                        let focused = AX.pid(of: window).flatMap { AX.element(kAXFocusedWindowAttribute, of: AX.application(pid: $0)) } == window
                        return (focused ? 0 : 1, AX.bool(kAXMinimizedAttribute, of: window) == true ? 1 : 0, AX.windowID(of: window) ?? .max)
                    }
                    return rank(left) < rank(right)
                }
                if let fresh = eligible.first(where: { !before.contains($0) }) { return fresh }
                return reuse && (!preferNew || attempt == 49) ? eligible.first : nil
            }
            if let found { return found }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw reuse ? LaunchError.noReusableWindow(name) : LaunchError.noWindow(name)
    }

    private static func waitForNewWindow(pid: pid_t, name: String) async throws -> AXElement {
        for _ in 0..<50 {
            try Task.checkCancellation()
            let found = await AX.perform { WindowInventory.windows(ofPID: pid).first }
            if let found { return found }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw LaunchError.noWindow(name)
    }
}
