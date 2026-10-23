import AppKit

public enum ZoneGeometry {
    public static func bounds(for zone: Zone, in snapshot: DisplaySnapshot) -> CGRect? {
        guard let display = DisplayRegistry.resolve(zone.monitor, in: snapshot) else { return nil }
        let clamped = zone.clamped()
        return Geo.rect(percentX: clamped.x, y: clamped.y, w: clamped.w, h: clamped.h, in: display.workAreaAX)
    }
}

public struct LaunchResult: Sendable {
    public var planned = 0
    public var placed = 0
    public var firstError: String?
    public var zoneCount = 0
    public var cancelled = false
}

@MainActor
public final class WorkspaceLauncher {
    public static let shared = WorkspaceLauncher()

    public private(set) var isLaunching = false
    private var generation = 0
    private var driftTasks: [Task<Void, Never>] = []

    public init() {}

    public func cancel() {
        generation += 1
        for task in driftTasks { task.cancel() }
        driftTasks.removeAll()
    }

    public func activate(_ workspace: Workspace, programs: [Program],
                         snapshot: DisplaySnapshot = DisplayRegistry.current) async -> LaunchResult? {
        guard !isLaunching else { return nil }
        cancel()
        let token = generation
        isLaunching = true
        defer { isLaunching = false }

        var result = LaunchResult()
        let desktops = SpaceRegistry.shared.snapshot()
        var claimed: Set<AXElement> = []
        result.zoneCount = workspace.zones.count

        for zone in workspace.zones {
            guard generation == token, !Task.isCancelled else { result.cancelled = true; break }
            guard let programName = zone.program, !programName.isEmpty else { continue }
            guard let program = programs.first(where: { $0.name.caseInsensitiveCompare(programName) == .orderedSame }) else {
                record(&result, error: "\(programName) is not in the program library.")
                result.planned += 1
                continue
            }
            guard let target = ZoneGeometry.bounds(for: zone, in: snapshot) else {
                record(&result, error: "\(programName): its display is not connected.")
                result.planned += 1
                continue
            }

            result.planned += 1
            do {
                let window = try await AppLauncher.launch(program, excluding: claimed, desktopSnapshot: desktops)
                try check(token)
                claimed.insert(window)
                let outcome = try await place(window, into: target, label: program.name, token: token, desktops: desktops)
                if outcome.failure == .desktopChanged { result.cancelled = true; break }
                if outcome.succeeded {
                    result.placed += 1
                } else {
                    record(&result, error: "\(program.name): the window would not move.")
                }
            } catch is CancellationError {
                result.cancelled = true
                break
            } catch {
                record(&result, error: error.localizedDescription)
            }
        }

        if result.cancelled { Log.write("launch stopped: desktop or display changed") }
        return result
    }

    private func check(_ token: Int) throws {
        if generation != token || Task.isCancelled { throw CancellationError() }
    }

    private func place(_ window: AXElement, into target: CGRect, label: String, token: Int, desktops: SpaceSnapshot) async throws -> WindowPlacer.Outcome {
        let validation: (@Sendable () -> Bool)?
        if desktops.available {
            validation = { SpaceRegistry.shared.windowIsOnDesktop(window, expected: desktops) }
        } else {
            validation = nil
        }
        try await Task.sleep(for: .milliseconds(400))
        try check(token)
        var outcome = await SnapEngine.snap(window: window, to: target, label: label, validation: validation)
        try await Task.sleep(for: .milliseconds(500))
        try check(token)
        let second = await SnapEngine.snap(window: window, to: target, label: "\(label) (settle)", validation: validation)
        try check(token)
        if second.isExact || outcome.failure != nil { outcome = second }
        watchForDrift(window, target: target, label: label, token: token, validation: validation)
        return outcome
    }

    private func watchForDrift(_ window: AXElement, target: CGRect, label: String, token: Int, validation: (@Sendable () -> Bool)?) {
        let task = Task {
            for _ in 0..<5 {
                do { try await Task.sleep(for: .milliseconds(500)); try check(token) }
                catch { return }
                let drifted = await AX.perform { () -> Bool in
                    guard let frame = AX.frame(of: window) else { return false }
                    return !Geo.matches(frame, target, tolerance: 4)
                }
                guard generation == token, !Task.isCancelled else { return }
                guard validation?() != false else { return }
                guard drifted else { continue }
                Log.write("re-applying \(label): the app moved its own window")
                _ = await SnapEngine.snap(window: window, to: target, label: "\(label) (drift)", validation: validation)
            }
        }
        driftTasks.append(task)
    }

    private func record(_ result: inout LaunchResult, error: String) {
        Log.error("launch: \(error)")
        if result.firstError == nil { result.firstError = error }
    }
}
