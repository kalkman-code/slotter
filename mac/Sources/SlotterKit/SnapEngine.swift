import AppKit

@MainActor
public enum SnapEngine {
    public static var onFeedback: ((String, String, Bool) -> Void)?

    public static func perform(_ action: SnapAction) {
        Task { await run(action) }
    }

    private static func run(_ action: SnapAction) async {
        guard AX.isTrusted else {
            onFeedback?("Accessibility not granted", "Slotter cannot move windows until you allow it.", false)
            return
        }
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        let pid = front.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }

        let snapshot = DisplayRegistry.current
        guard let found = await AX.perform({ () -> WindowSnapshot? in
            let application = AX.application(pid: pid)
            guard let window = WindowPlacer.focusedWindow(of: application),
                  let frame = AX.frame(of: window) else { return nil }
            return WindowSnapshot(window: window, frame: frame)
        }) else { return }

        guard let display = snapshot.display(bestFor: found.frame) else { return }

        var target: CGRect?
        switch action {
        case .restore:
            target = FrameHistory.shared.swap(found.window, pid: pid, current: found.frame)
        case .nextDisplay, .previousDisplay:
            let destination = action == .nextDisplay
                ? snapshot.next(after: display)
                : snapshot.previous(before: display)
            guard let destination else { return }
            let unit = Geo.fraction(of: found.frame, in: display.workAreaAX)
            target = Geo.denormalize(unit, into: destination.workAreaAX)
        default:
            target = MagnetLayouts.frame(for: action, work: display.workAreaAX, current: found.frame)
        }

        guard let target else { return }
        if action != .restore {
            FrameHistory.shared.record(found.window, pid: pid, frame: found.frame)
        }

        await snap(window: found.window, to: target, label: "\(action.title) · \(front.localizedName ?? "app")")
    }

    @discardableResult
    public static func snap(window: AXElement, to target: CGRect, label: String) async -> WindowPlacer.Outcome {
        var outcome = await AX.perform { WindowPlacer.place(window, into: target) }
        var attempts = 0

        while case .retryable = outcome.failure, attempts < 8 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(150))
            outcome = await AX.perform { WindowPlacer.place(window, into: target) }
        }

        if let failure = outcome.failure {
            Log.error("snap failed: \(label) want=\(Geo.describe(target)) failure=\(failure) attempts=\(attempts)")
        } else {
            Log.write("snapped \(label) -> \(Geo.describe(target)) "
                + "got=\(outcome.applied.map(Geo.describe) ?? "nil") exact=\(outcome.isExact)")
        }
        return outcome
    }
}

public struct WindowSnapshot: Sendable {
    public let window: AXElement
    public let frame: CGRect

    public init(window: AXElement, frame: CGRect) {
        self.window = window
        self.frame = frame
    }
}
