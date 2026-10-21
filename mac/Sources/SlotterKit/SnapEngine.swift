import AppKit

@MainActor
public enum SnapEngine {
    public static var onFeedback: ((String, String, Bool) -> Void)?
    private static var ownWindowFrames: [Int: CGRect] = [:]

    public static func perform(_ action: SnapAction) {
        Task { await run(action) }
    }

    private static func run(_ action: SnapAction) async {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        let pid = front.processIdentifier
        if pid == ProcessInfo.processInfo.processIdentifier {
            snapOwnWindow(action)
            return
        }
        guard AX.isTrusted else {
            onFeedback?("Accessibility not granted", "Slotter cannot move other apps’ windows until you allow it.", false)
            return
        }

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

    private static func snapOwnWindow(_ action: SnapAction) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              !(window is NSPanel), window.isVisible, !window.isMiniaturized,
              window.level == .normal, window.styleMask.contains(.titled) else { return }

        let snapshot = DisplayRegistry.current
        let current = Geo.ax(fromCocoa: window.frame, flipY: snapshot.flipY)
        guard let display = snapshot.display(bestFor: current) else { return }
        let key = window.windowNumber
        let target: CGRect?
        if action == .restore {
            target = ownWindowFrames[key]
            ownWindowFrames[key] = current
        } else if action == .nextDisplay || action == .previousDisplay {
            let destination = action == .nextDisplay
                ? snapshot.next(after: display)
                : snapshot.previous(before: display)
            target = destination.map { Geo.denormalize(Geo.fraction(of: current, in: display.workAreaAX), into: $0.workAreaAX) }
            ownWindowFrames[key] = current
        } else {
            target = MagnetLayouts.frame(for: action, work: display.workAreaAX, current: current)
            ownWindowFrames[key] = current
        }
        guard let target else { return }
        window.setFrame(Geo.cocoa(fromAX: target, flipY: snapshot.flipY), display: true, animate: false)
        Log.write("snapped Slotter window · \(action.title) -> \(Geo.describe(target))")
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
