import Foundation

@MainActor
public final class ConfigStore {
    public static let shared = ConfigStore()

    nonisolated public static let directory: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Slotter", directoryHint: .isDirectory)

    nonisolated public static let url: URL = directory.appending(path: "profiles.ini")

    private static let zoneKeyPrefixes = ["zone", "monkey", "monuuid", "mondup", "prog", "zoneplate"]

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var debounce: DispatchWorkItem?
    private var suppressUntil = Date.distantPast

    public var onExternalChange: (() -> Void)?

    public init() {}

    /// Slotter was called Snappy before 1.0; a first run carries Snappy's workspaces over.
    static let snappyURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Snappy/profiles.ini")

    public func writeDefaultIfMissing() {
        guard !FileManager.default.fileExists(atPath: Self.url.path) else { return }
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)

        if (try? FileManager.default.copyItem(at: Self.snappyURL, to: Self.url)) != nil {
            Log.write("carried Snappy's config over from \(Self.snappyURL.path)")
            return
        }

        let config = SlotterConfig(workspaces: [Workspace(name: "Workspace 1")],
                                   lastWorkspace: "Workspace 1")

        var document = IniDocument(text: Self.header)
        write(config, into: &document)
        try? document.serialized().write(to: Self.url, atomically: true, encoding: .utf8)
        Log.write("wrote default config to \(Self.url.path)")
    }

    public func load() -> SlotterConfig {
        guard let text = try? String(contentsOf: Self.url, encoding: .utf8) else { return SlotterConfig() }
        return Self.parse(IniDocument(text: text))
    }

    func serializedConfig(_ config: SlotterConfig, preserving text: String = "") -> String {
        var document = IniDocument(text: text.isEmpty ? Self.header : text)
        write(config, into: &document)
        return document.serialized()
    }

    @discardableResult
    public func save(_ config: SlotterConfig) -> Bool {
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
            return false
        }
        restartWatchingIfNeeded()
        return true
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

    private func write(_ config: SlotterConfig, into document: inout IniDocument) {
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
                if let plateID = clamped.plateID { pairs.append(("ZonePlate\(n)", plateID.uuidString)) }
            }
            pairs.insert(("WorkspaceID", workspace.id.uuidString), at: 0)
            for (index, plate) in workspace.virtualPlates.enumerated() {
                let n = index + 1
                pairs.append(("VirtualPlate\(n)ID", plate.id.uuidString))
                pairs.append(("VirtualPlate\(n)Name", plate.name))
                pairs.append(("VirtualPlate\(n)Desktop", plate.desktopID ?? ""))
                pairs.append(("VirtualPlate\(n)AutoName", plate.followsDesktopName ? "1" : "0"))
                pairs.append(("VirtualPlate\(n)ClosedDesktop", plate.closedDesktopLabel ?? ""))
                pairs.append(("VirtualPlate\(n)Monitor", "\(plate.monitor.ordinal)|\(plate.monitor.uuid ?? "")|\(plate.monitor.legacyKey ?? "")|\(plate.monitor.duplicateIndex)"))
            }
            pairs.append(("VirtualPlateCount", String(workspace.virtualPlates.count)))
            document.replaceSection(workspace.name, removingKeysMatching: {
                $0.caseInsensitiveCompare("WorkspaceID") == .orderedSame || Self.isZoneKey($0)
                    || $0.lowercased().hasPrefix("virtualplate")
            }, with: pairs)
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

        let pairs = config.shortcuts.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) }
        document.replaceSection("Shortcuts", removingKeysMatching: { _ in true }, with: pairs)

        document.removeSection("SpaceBindings")
        var setupPairs: [(key: String, value: String)] = [("Count", String(config.desktopSetups.count))]
        for (index, setup) in config.desktopSetups.enumerated() {
            let n = index + 1
            setupPairs.append(("Name\(n)", setup.name))
            setupPairs.append(("ZoneCount\(n)", String(setup.zones.count)))
            for (zoneIndex, zone) in setup.zones.enumerated() {
                let zone = zone.clamped()
                let key = "\(n)_\(zoneIndex + 1)"
                setupPairs.append(("Zone\(key)", "\(number(zone.x)),\(number(zone.y)),\(number(zone.w)),\(number(zone.h))"))
                if let program = zone.program { setupPairs.append(("Program\(key)", program)) }
            }
        }
        document.replaceSection("DesktopSetups", removingKeysMatching: { _ in true }, with: setupPairs)
    }

    static func parse(_ document: IniDocument) -> SlotterConfig {
        var config = SlotterConfig()
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
            let stableID = UUID(uuidString: document.string(name, "WorkspaceID")) ?? UUID()
            var workspace = Workspace(name: name, id: stableID)
            let plateCount = min(document.int(name, "VirtualPlateCount"), document.pairs(in: name).count)
            if plateCount > 0 {
                for plateIndex in 1...plateCount {
                    let prefix = "VirtualPlate\(plateIndex)"
                    guard let plateID = UUID(uuidString: document.string(name, "\(prefix)ID")) else { continue }
                    let fields = document.string(name, "\(prefix)Monitor").split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                    guard fields.count == 4, let ordinal = Int(fields[0]), let duplicate = Int(fields[3]) else { continue }
                    workspace.virtualPlates.append(VirtualPlate(
                        id: plateID, name: document.string(name, "\(prefix)Name"),
                        monitor: MonitorRef(ordinal: ordinal, uuid: fields[1].isEmpty ? nil : fields[1],
                                            legacyKey: fields[2].isEmpty ? nil : fields[2], duplicateIndex: duplicate),
                        desktopID: document.string(name, "\(prefix)Desktop").isEmpty ? nil : document.string(name, "\(prefix)Desktop"),
                        followsDesktopName: document.string(name, "\(prefix)AutoName").isEmpty ? nil : document.bool(name, "\(prefix)AutoName"),
                        closedDesktopLabel: document.string(name, "\(prefix)ClosedDesktop").isEmpty ? nil : document.string(name, "\(prefix)ClosedDesktop")))
                }
            }
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
                    program: program.isEmpty ? nil : program,
                    plateID: UUID(uuidString: document.string(name, "ZonePlate\(index)").trimmingCharacters(in: .whitespaces))).clamped())
                index += 1
            }
            config.workspaces.append(workspace)
        }

        // Records are contiguous; a corrupt count cannot require more lookups than the file has keys.
        let count = min(document.int("Programs", "Count"), document.pairs(in: "Programs").count)
        for index in stride(from: 1, through: count, by: 1) {
            let name = document.string("Programs", "Name\(index)")
            let path = document.string("Programs", "Exe\(index)")
            guard !name.isEmpty, !path.isEmpty else { continue }
            config.programs.append(Program(name: name,
                                           path: path,
                                           arguments: document.string("Programs", "Args\(index)"),
                                           newInstance: document.bool("Programs", "New\(index)")))
        }

        for index in 0..<max(0, min(1000, document.int("DesktopSetups", "Count"))) {
            let n = index + 1
            let name = document.string("DesktopSetups", "Name\(n)")
            guard !name.isEmpty else { continue }
            var zones: [Zone] = []
            for zoneIndex in 0..<max(0, min(400, document.int("DesktopSetups", "ZoneCount\(n)"))) {
                let key = "\(n)_\(zoneIndex + 1)"
                let fields = document.string("DesktopSetups", "Zone\(key)").split(separator: ",", omittingEmptySubsequences: false)
                let values = fields.compactMap { Double($0) }
                guard fields.count == 4, values.count == 4, values.allSatisfy(\.isFinite),
                      values[0] >= 0, values[1] >= 0, values[2] >= 1, values[3] >= 1,
                      values[0] + values[2] <= 100.05, values[1] + values[3] <= 100.05 else { continue }
                let program = document.string("DesktopSetups", "Program\(key)")
                zones.append(Zone(monitor: MonitorRef(ordinal: 1), x: values[0], y: values[1], w: values[2], h: values[3], program: program.isEmpty ? nil : program).clamped())
            }
            if !zones.isEmpty { config.desktopSetups.append(DesktopSetup(name: name, zones: zones)) }
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
    ; Slotter config — edit via the menu bar Settings window, or by hand here.
    ; Zone<N> = Monitor,XPct,YPct,WPct,HPct   (percent of that monitor's visible area)
    ; Prog<N> = <program name from [Programs]>  (which program launches into Zone<N>)
    ; MonUUID<N> identifies the display; MonKey<N> and the Monitor ordinal are fallbacks.
    """
}
