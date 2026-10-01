import AppKit
import ApplicationServices

@MainActor
public final class DragSnapService {
    public struct Callbacks {
        public var present: ([SnapTarget], CGFloat) -> Void
        public var reveal: () -> Void
        public var highlight: (SnapTarget?, CGFloat) -> Void
        public var dismiss: () -> Void

        public init(present: @escaping ([SnapTarget], CGFloat) -> Void,
                    reveal: @escaping () -> Void,
                    highlight: @escaping (SnapTarget?, CGFloat) -> Void,
                    dismiss: @escaping () -> Void) {
            self.present = present
            self.reveal = reveal
            self.highlight = highlight
            self.dismiss = dismiss
        }
    }

    private struct Candidate {
        let window: AXElement
        let pid: pid_t
        let startFrame: CGRect
        let startMouse: CGPoint
        let downAt: Date
        let token: Int
    }

    private struct Session {
        let window: AXElement
        let pid: pid_t
        let zones: [SnapTarget]
        let edges: [SnapTarget]
        var highlighted: SnapTarget?
    }

    private enum Phase {
        case idle
        case arming(token: Int, downAt: CGPoint)
        case armed(Candidate)
        case dragging(Session)
    }

    nonisolated private static let contentRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole,
        kAXButtonRole, kAXCheckBoxRole, kAXPopUpButtonRole, kAXRadioButtonRole,
        kAXSliderRole, kAXIncrementorRole, kAXMenuItemRole, kAXMenuBarItemRole,
        kAXTableRole, kAXOutlineRole, kAXCellRole, kAXColumnRole, kAXRowRole,
        kAXImageRole, kAXListRole, "AXWebArea", "AXLink",
    ]

    public var workspaceProvider: (() -> Workspace?)?

    private let callbacks: Callbacks
    private var tap: MouseTap?
    private let watcher = MoveWatcher()
    private var phase = Phase.idle
    private var classifying = false
    private var token = 0
    private var expiry: Timer?
    private var flipY: CGFloat = 0
    private var suppressUntil = Date.distantPast

    public init(callbacks: Callbacks) {
        self.callbacks = callbacks
        watcher.onMoved = { [weak self] element in self?.windowMoved(element) }
        watcher.onResized = { [weak self] element in self?.windowResized(element) }
    }

    public func start() {
        guard tap == nil else { return }
        let tap = MouseTap { [weak self] sample in
            MainActor.assumeIsolated { self?.handle(sample) }
        }
        do {
            try tap.start()
            self.tap = tap
        } catch {
            Log.error("drag-snap unavailable: \(error)")
        }
    }

    public func stop() {
        cancel()
        tap?.stop()
        tap = nil
    }

    public func suppressSelfTriggers(for interval: TimeInterval = 0.3) {
        suppressUntil = Date().addingTimeInterval(interval)
    }

    public func cancel() {
        expiry?.invalidate()
        expiry = nil
        watcher.stop()
        if case .dragging = phase {
            callbacks.dismiss()
        } else {
            callbacks.dismiss()
        }
        phase = .idle
        pendingConfirmation = nil
        classifying = false
        token += 1
    }

    private func handle(_ sample: MouseTap.Sample) {
        switch sample.kind {
        case .down: beginArming(at: sample.location)
        case .drag: continueDrag(at: sample.location)
        case .up: finish(at: sample.location)
        }
    }

    private func beginArming(at point: CGPoint) {
        cancel()
        guard Date() > suppressUntil else { return }

        token += 1
        let current = token
        phase = .arming(token: current, downAt: point)
        flipY = DisplayRegistry.current.flipY

        AX.queue.async { [weak self] in
            let resolved = Self.resolveWindow(at: point)
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .arming(let armingToken, let downAt) = self.phase, armingToken == current else { return }
                guard let resolved else {
                    self.phase = .idle
                    return
                }
                self.phase = .armed(Candidate(window: resolved.window,
                                              pid: resolved.pid,
                                              startFrame: resolved.frame,
                                              startMouse: downAt,
                                              downAt: Date(),
                                              token: current))
                self.watcher.watch(pid: resolved.pid)
                self.prewarmTargets()
            }
        }
    }

    private func prewarmTargets() {
        let snapshot = DisplayRegistry.current
        flipY = snapshot.flipY
        let built = SnapTargetBuilder.build(workspace: workspaceProvider?(), snapshot: snapshot)
        guard case .armed(let candidate) = phase else { return }
        phase = .dragging(Session(window: candidate.window,
                                  pid: candidate.pid,
                                  zones: built.zones,
                                  edges: built.edges,
                                  highlighted: nil))
        pendingConfirmation = candidate
        callbacks.present(built.zones, flipY)
    }

    private var pendingConfirmation: Candidate?

    private func continueDrag(at point: CGPoint) {
        guard case .dragging(var session) = phase else { return }

        if let candidate = pendingConfirmation {
            let travelled = hypot(point.x - candidate.startMouse.x, point.y - candidate.startMouse.y)
            guard travelled >= 8, !classifying else { return }
            classifying = true
            classify(candidate)
            return
        }

        let target = SnapTargetBuilder.hit(at: point, zones: session.zones, edges: session.edges)
        guard target?.id != session.highlighted?.id else { return }
        session.highlighted = target
        phase = .dragging(session)
        callbacks.highlight(target, flipY)
    }

    private func classify(_ candidate: Candidate) {
        let window = candidate.window
        let start = candidate.startFrame
        let startMouse = candidate.startMouse

        AX.queue.async { [weak self] in
            let frame = AX.frame(of: window)
            let mouse = CGEvent(source: nil)?.location

            DispatchQueue.main.async {
                guard let self else { return }
                self.classifying = false
                guard case .dragging = self.phase,
                      self.pendingConfirmation?.token == candidate.token else { return }
                guard let frame, let mouse else { self.cancel(); return }

                if abs(frame.width - start.width) > 1 || abs(frame.height - start.height) > 1 {
                    Log.write("drag: resize — ignoring")
                    self.cancel()
                    return
                }

                let originDelta = CGPoint(x: frame.minX - start.minX, y: frame.minY - start.minY)
                let mouseDelta = CGPoint(x: mouse.x - startMouse.x, y: mouse.y - startMouse.y)
                let travelled = hypot(mouseDelta.x, mouseDelta.y)
                let moved = hypot(originDelta.x, originDelta.y)

                let tolerance = max(6, travelled * 0.35)
                let tracks = abs(originDelta.x - mouseDelta.x) <= tolerance
                    && abs(originDelta.y - mouseDelta.y) <= tolerance

                if moved >= 5 && tracks {
                    Log.write("drag: move confirmed by frame")
                    self.confirmDrag()
                    return
                }

                let elapsed = Date().timeIntervalSince(candidate.downAt)
                if travelled >= 24 && moved < 3 && elapsed >= 0.5 {
                    Log.write("drag: content — ignoring "
                        + "(mouse \(Int(travelled))pt, window \(Int(moved))pt, \(Int(elapsed * 1000))ms)")
                    self.cancel()
                }
            }
        }
    }

    private func confirmDrag() {
        guard pendingConfirmation != nil else { return }
        pendingConfirmation = nil
        callbacks.reveal()

        expiry?.invalidate()
        expiry = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    private func windowMoved(_ element: AXElement) {
        guard let candidate = pendingConfirmation, candidate.window == element else { return }
        Log.write("drag: move confirmed by observer")
        confirmDrag()
    }

    private func windowResized(_ element: AXElement) {
        guard let candidate = pendingConfirmation, candidate.window == element else { return }
        let start = candidate.startFrame
        let token = candidate.token

        AX.queue.async { [weak self] in
            let frame = AX.frame(of: element)
            DispatchQueue.main.async {
                guard let self, self.pendingConfirmation?.token == token else { return }
                guard let frame else { return }
                guard abs(frame.width - start.width) > 1 || abs(frame.height - start.height) > 1 else { return }
                Log.write("drag: resize confirmed by observer — ignoring")
                self.cancel()
            }
        }
    }

    private func finish(at point: CGPoint) {
        guard case .dragging(let session) = phase else {
            cancel()
            return
        }
        let pending = pendingConfirmation
        let target = SnapTargetBuilder.hit(at: point, zones: session.zones, edges: session.edges)

        expiry?.invalidate()
        expiry = nil
        watcher.stop()
        pendingConfirmation = nil
        classifying = false
        phase = .idle
        callbacks.dismiss()

        guard let target else { return }
        suppressSelfTriggers()

        let window = session.window
        let pid = session.pid

        guard let pending else {
            Task { await apply(window: window, pid: pid, target: target) }
            return
        }

        Task {
            for attempt in 0..<3 {
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(120)) }
                let verdict = await AX.perform { () -> Bool? in
                    guard Self.isSnappable(window), let frame = AX.frame(of: window) else { return false }
                    if abs(frame.width - pending.startFrame.width) > 1
                        || abs(frame.height - pending.startFrame.height) > 1 { return false }
                    let moved = hypot(frame.minX - pending.startFrame.minX,
                                      frame.minY - pending.startFrame.minY)
                    return moved >= 5 ? true : nil
                }
                if verdict == true {
                    await apply(window: window, pid: pid, target: target)
                    return
                }
                if verdict == false { break }
            }
            Log.write("drop ignored: the window never moved")
        }
    }

    private func apply(window: AXElement, pid: pid_t, target: SnapTarget) async {
        let current = await AX.perform { AX.frame(of: window) }
        if let current { FrameHistory.shared.record(window, pid: pid, frame: current) }
        _ = await SnapEngine.snap(window: window, to: target.frame, label: "drop · \(target.caption)")
    }

    nonisolated private static func resolveWindow(at point: CGPoint) -> (window: AXElement, pid: pid_t, frame: CGRect)? {
        guard let hit = AX.element(at: point) else { return nil }
        if let role = AX.role(of: hit), contentRoles.contains(role) { return nil }
        guard let window = enclosingWindow(of: hit) else { return nil }
        guard let pid = AX.pid(of: window), pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        guard let frame = AX.frame(of: window), frame.width > 1, frame.height > 1 else { return nil }
        return (window, pid, frame)
    }

    nonisolated private static func isSnappable(_ window: AXElement) -> Bool {
        WindowPlacer.isStandardWindow(window) && AX.isSettable(kAXPositionAttribute, on: window)
    }

    nonisolated private static func enclosingWindow(of element: AXElement) -> AXElement? {
        if let direct = AX.element(kAXWindowAttribute, of: element) { return direct }
        if AX.role(of: element) == kAXWindowRole { return element }
        if let top = AX.element(kAXTopLevelUIElementAttribute, of: element),
           AX.role(of: top) == kAXWindowRole { return top }

        var current = element
        for _ in 0..<12 {
            guard let parent = AX.element(kAXParentAttribute, of: current) else { return nil }
            if AX.role(of: parent) == kAXWindowRole { return parent }
            current = parent
        }
        return nil
    }
}
