import Foundation

@MainActor
public final class ConfigStore {
    public static let shared = ConfigStore()

    public static let directory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Snappy", directoryHint: .isDirectory)

    public static let url: URL = directory.appending(path: "profiles.ini")

    private static let zoneKeyPrefixes = ["zone", "monkey", "monuuid", "mondup", "prog"]

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var debounce: DispatchWorkItem?
    private var suppressUntil = Date.distantPast

    public var onExternalChange: (() -> Void)?

    public init() {}

    public func writeDefaultIfMissing() {
        guard !FileManager.default.fileExists(atPath: Self.url.path) else { return }
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)

        let monitor = DisplayRegistry.current.displays.first
        let reference = monitor.map { DisplayRegistry.reference(for: $0) } ?? MonitorRef(ordinal: 1)
        let config = SnappyConfig(
            workspaces: [Workspace(name: "Example", zones: [
                Zone(monitor: reference, x: 0, y: 0, w: 50, h: 100, program: "Safari"),
                Zone(monitor: reference, x: 50, y: 0, w: 50, h: 100, program: "Finder"),
            ])],
            programs: [
                Program(name: "Safari", path: "/Applications/Safari.app"),
                Program(name: "Finder", path: "/System/Library/CoreServices/Finder.app"),
            ],
            lastWorkspace: "Example")

        var document = IniDocument(text: Self.header)
        write(config, into: &document)
        try? document.serialized().write(to: Self.url, atomically: true, encoding: .utf8)
        Log.write("wrote default config to \(Self.url.path)")
    }

    public func load() -> SnappyConfig {
        guard let text = try? String(contentsOf: Self.url, encoding: .utf8) else { return SnappyConfig() }
        return Self.parse(IniDocument(text: text))
    }

    public func save(_ config: SnappyConfig) {
        var document: IniDocument
        if let text = try? String(contentsOf: Self.url, encoding: .utf8) {
            document = IniDocument(text: text)
        } else {
            document = IniDocument(text: Self.header)
        }

        let existing = Set(document.string("Profiles", "List")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        let wanted = Set(config.workspaces.map(\.name))
        for stale in existing.subtracting(wanted) { document.removeSection(stale) }

        write(config, into: &document)

        suppressUntil = Date().addingTimeInterval(1.0)
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try document.serialized().write(to: Self.url, atomically: true, encoding: .utf8)
        } catch {
            Log.error("save config: \(error.localizedDescription)")
        }
        restartWatchingIfNeeded()
    }

    public func startWatching() {
        stopWatching()
        guard FileManager.default.fileExists(atPath: Self.url.path) else { return }
        descriptor = open(Self.url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main)
        source.setEventHandler { [weak self] in self?.fileChanged() }
        source.setCancelHandler { [descriptor = self.descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        source.resume()
        self.source = source
    }

    public func stopWatching() {
        source?.cancel()
        source = nil
        descriptor = -1
    }

    private func restartWatchingIfNeeded() {
        guard source != nil else { return }
        startWatching()
    }

    private func fileChanged() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restartWatchingIfNeeded()
            guard Date() > self.suppressUntil else { return }
            Log.write("config changed on disk")
            self.onExternalChange?()
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func write(_ config: SnappyConfig, into document: inout IniDocument) {
        document.set("Profiles", "List", config.workspaces.map(\.name).joined(separator: ","))
        document.set("Panel", "LastProfile", config.lastWorkspace)
        document.set("Settings", "StartAtLogin", config.startAtLogin ? "1" : "0")

        for workspace in config.workspaces {
            var pairs: [(key: String, value: String)] = []
            for (index, zone) in workspace.zones.enumerated() {
                let n = index + 1
                let clamped = zone.clamped()
                pairs.append(("Zone\(n)", "\(clamped.monitor.ordinal),\(number(clamped.x)),\(number(clamped.y)),"
                    + "\(number(clamped.w)),\(number(clamped.h))"))
                if let uuid = clamped.monitor.uuid, !uuid.isEmpty { pairs.append(("MonUUID\(n)", uuid)) }
                if let key = clamped.monitor.legacyKey, !key.isEmpty { pairs.append(("MonKey\(n)", key)) }
                if clamped.monitor.duplicateIndex != 0 {
                    pairs.append(("MonDup\(n)", String(clamped.monitor.duplicateIndex)))
                }
                if let program = clamped.program, !program.isEmpty { pairs.append(("Prog\(n)", program)) }
            }
            document.replaceSection(workspace.name, removingKeysMatching: Self.isZoneKey, with: pairs)
        }

        var programPairs: [(key: String, value: String)] = [("Count", String(config.programs.count))]
        for (index, program) in config.programs.enumerated() {
            let n = index + 1
            programPairs.append(("Name\(n)", program.name))
            programPairs.append(("Exe\(n)", program.path))
            programPairs.append(("Args\(n)", program.arguments))
            if program.newInstance { programPairs.append(("New\(n)", "1")) }
        }
        document.replaceSection("Programs", removingKeysMatching: Self.isProgramKey, with: programPairs)

        if !config.shortcuts.isEmpty {
            let pairs = config.shortcuts.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) }
            document.replaceSection("Shortcuts", removingKeysMatching: { _ in true }, with: pairs)
        }
    }

    private static func parse(_ document: IniDocument) -> SnappyConfig {
        var config = SnappyConfig()
        config.lastWorkspace = document.string("Panel", "LastProfile")
        config.startAtLogin = document.bool("Settings", "StartAtLogin",
                                            default: document.bool("Settings", "StartWithWindows"))

        for (key, value) in document.pairs(in: "Shortcuts") { config.shortcuts[key] = value }

        let names = document.string("Profiles", "List")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for name in names {
            guard document.hasSection(name) else { continue }
            var workspace = Workspace(name: name)
            var index = 1
            while true {
                let raw = document.string(name, "Zone\(index)")
                if raw.isEmpty { break }
                let fields = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard fields.count >= 5,
                      let ordinal = Int(fields[0]),
                      let x = Double(fields[1]), let y = Double(fields[2]),
                      let w = Double(fields[3]), let h = Double(fields[4]) else { index += 1; continue }

                let uuid = document.string(name, "MonUUID\(index)")
                let legacy = document.string(name, "MonKey\(index)")
                let duplicate = document.int(name, "MonDup\(index)")
                let program = document.string(name, "Prog\(index)")

                workspace.zones.append(Zone(
                    monitor: MonitorRef(ordinal: ordinal,
                                        uuid: uuid.isEmpty ? nil : uuid,
                                        legacyKey: legacy.isEmpty ? nil : legacy,
                                        duplicateIndex: duplicate),
                    x: x, y: y, w: w, h: h,
                    program: program.isEmpty ? nil : program).clamped())
                index += 1
            }
            config.workspaces.append(workspace)
        }

        let count = document.int("Programs", "Count")
        for index in stride(from: 1, through: count, by: 1) {
            let name = document.string("Programs", "Name\(index)")
            let path = document.string("Programs", "Exe\(index)")
            guard !name.isEmpty, !path.isEmpty else { continue }
            config.programs.append(Program(name: name,
                                           path: path,
                                           arguments: document.string("Programs", "Args\(index)"),
                                           newInstance: document.bool("Programs", "New\(index)")))
        }

        return config
    }

    private static func isZoneKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return zoneKeyPrefixes.contains { prefix in
            lowered.hasPrefix(prefix) && Int(lowered.dropFirst(prefix.count)) != nil
        }
    }

    private static func isProgramKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        if lowered == "count" { return true }
        for prefix in ["name", "exe", "args", "new"] where lowered.hasPrefix(prefix) {
            if Int(lowered.dropFirst(prefix.count)) != nil { return true }
        }
        return false
    }

    private func number(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%g", rounded)
    }

    private static let header = """
    ; Snappy config — edit via the menu bar Settings window, or by hand here.
    ; Zone<N> = Monitor,XPct,YPct,WPct,HPct   (percent of that monitor's visible area)
    ; Prog<N> = <program name from [Programs]>  (which program launches into Zone<N>)
    ; MonUUID<N> identifies the display; MonKey<N> and the Monitor ordinal are fallbacks.
    """
}
