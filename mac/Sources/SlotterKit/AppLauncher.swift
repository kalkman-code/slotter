import AppKit

public enum AppLauncher {
    public enum LaunchError: LocalizedError, Sendable {
        case missingPath(String)
        case launchFailed(String, String)
        case noWindow(String)

        public var errorDescription: String? {
            switch self {
            case .missingPath(let name): return "\(name): nothing exists at that path."
            case .launchFailed(let name, let reason): return "\(name): \(reason)"
            case .noWindow(let name): return "\(name): no window appeared in time."
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

    public static func launch(_ program: Program) async throws -> AXElement {
        let path = program.path.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            throw LaunchError.missingPath(program.name)
        }

        let url = URL(fileURLWithPath: path)
        let arguments = tokenise(program.arguments)

        if program.isAppBundle {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
                throw LaunchError.launchFailed(program.name, "not a readable application bundle.")
            }
            let before = await AX.perform { WindowInventory.windows(ofBundleID: bundleID) }

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

            return try await waitForNewWindow(bundleID: bundleID, excluding: before, name: program.name)
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

    private static func waitForNewWindow(bundleID: String,
                                         excluding before: Set<AXElement>,
                                         name: String) async throws -> AXElement {
        for _ in 0..<50 {
            let found = await AX.perform { () -> AXElement? in
                WindowInventory.windows(ofBundleID: bundleID).subtracting(before).first
            }
            if let found { return found }
            try? await Task.sleep(for: .milliseconds(100))
        }
        throw LaunchError.noWindow(name)
    }

    private static func waitForNewWindow(pid: pid_t, name: String) async throws -> AXElement {
        for _ in 0..<50 {
            let found = await AX.perform { WindowInventory.windows(ofPID: pid).first }
            if let found { return found }
            try? await Task.sleep(for: .milliseconds(100))
        }
        throw LaunchError.noWindow(name)
    }
}
