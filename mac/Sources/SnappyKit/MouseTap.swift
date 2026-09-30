import AppKit
import os

public final class MouseTap: @unchecked Sendable {
    public struct Sample: Sendable {
        public enum Kind: Sendable { case down, drag, up }
        public let kind: Kind
        public let location: CGPoint
    }

    public enum StartError: Error, Sendable {
        case notTrusted
        case tapRefused
    }

    private struct Pending {
        var latestDrag: CGPoint?
        var scheduled = false
    }

    private let onSample: @Sendable (Sample) -> Void
    private let pending = OSAllocatedUnfairLock(initialState: Pending())
    private let stopping = OSAllocatedUnfairLock(initialState: false)
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var watchdog: Timer?

    public init(onSample: @escaping @Sendable (Sample) -> Void) {
        self.onSample = onSample
    }

    public var isEnabled: Bool {
        guard let port else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    public func start() throws {
        guard AX.isTrusted else { throw StartError.notTrusted }
        guard port == nil else { return }

        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: mouseTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            throw StartError.tapRefused
        }

        stopping.withLock { $0 = false }
        port = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        let thread = Thread { [weak self] in
            guard let self, let source = self.source, let port = self.port else { return }
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "com.tobykalkman.snappy.mousetap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread

        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, let port = self.port else { return }
            if !CGEvent.tapIsEnabled(tap: port) {
                Log.error("mouse tap was disabled — re-enabling")
                CGEvent.tapEnable(tap: port, enable: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer

        Log.write("mouse tap started")
    }

    public func stop() {
        guard port != nil else { return }
        stopping.withLock { $0 = true }
        watchdog?.invalidate()
        watchdog = nil

        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let runLoop, let source {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFRunLoopStop(runLoop)
        }
        source = nil
        port = nil
        runLoop = nil
        thread = nil
        Log.write("mouse tap stopped")
    }

    fileprivate func handle(type: CGEventType, location: CGPoint) {
        switch type {
        case .leftMouseDown:
            deliver(Sample(kind: .down, location: location))
        case .leftMouseUp:
            pending.withLock { $0.latestDrag = nil }
            deliver(Sample(kind: .up, location: location))
        case .leftMouseDragged:
            let shouldSchedule = pending.withLock { state -> Bool in
                state.latestDrag = location
                guard !state.scheduled else { return false }
                state.scheduled = true
                return true
            }
            guard shouldSchedule else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let point = self.pending.withLock { state -> CGPoint? in
                    state.scheduled = false
                    defer { state.latestDrag = nil }
                    return state.latestDrag
                }
                guard let point else { return }
                self.onSample(Sample(kind: .drag, location: point))
            }
        default:
            break
        }
    }

    fileprivate func reEnable() {
        guard !stopping.withLock({ $0 }), let port else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        Log.error("mouse tap re-enabled after being disabled by the system")
    }

    private func deliver(_ sample: Sample) {
        DispatchQueue.main.async { [weak self] in self?.onSample(sample) }
    }
}

private func mouseTapCallback(proxy: CGEventTapProxy,
                              type: CGEventType,
                              event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MouseTap>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        tap.reEnable()
        return nil
    }

    tap.handle(type: type, location: event.location)
    return Unmanaged.passUnretained(event)
}
