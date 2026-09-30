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
}

@MainActor
public final class WorkspaceLauncher {
    public static let shared = WorkspaceLauncher()

    public private(set) var isLaunching = false

    public init() {}

    public func activate(_ workspace: Workspace, programs: [Program]) async -> LaunchResult? {
        guard !isLaunching else { return nil }
        isLaunching = true
        defer { isLaunching = false }

        let snapshot = DisplayRegistry.current
        var result = LaunchResult()
        result.zoneCount = workspace.zones.count

        for zone in workspace.zones {
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
                let window = try await AppLauncher.launch(program)
                let outcome = await place(window, into: target, label: program.name)
                if outcome.succeeded {
                    result.placed += 1
                } else {
                    record(&result, error: "\(program.name): the window would not move.")
                }
            } catch {
                record(&result, error: error.localizedDescription)
            }
        }

        return result
    }

    private func place(_ window: AXElement, into target: CGRect, label: String) async -> WindowPlacer.Outcome {
        try? await Task.sleep(for: .milliseconds(400))
        var outcome = await SnapEngine.snap(window: window, to: target, label: label)
        try? await Task.sleep(for: .milliseconds(500))
        let second = await SnapEngine.snap(window: window, to: target, label: "\(label) (settle)")
        if second.isExact || outcome.failure != nil { outcome = second }
        watchForDrift(window, target: target, label: label)
        return outcome
    }

    private func watchForDrift(_ window: AXElement, target: CGRect, label: String) {
        Task {
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(500))
                let drifted = await AX.perform { () -> Bool in
                    guard let frame = AX.frame(of: window) else { return false }
                    return !Geo.matches(frame, target, tolerance: 4)
                }
                guard drifted else { continue }
                Log.write("re-applying \(label): the app moved its own window")
                _ = await SnapEngine.snap(window: window, to: target, label: "\(label) (drift)")
            }
        }
    }

    private func record(_ result: inout LaunchResult, error: String) {
        Log.error("launch: \(error)")
        if result.firstError == nil { result.firstError = error }
    }
}
