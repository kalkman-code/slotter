import AppKit
import ApplicationServices

public enum WindowPlacer {
    public static let fullScreenAttribute = "AXFullScreen"

    public enum Failure: Sendable, Equatable {
        case notTrusted
        case positionNotSettable
        case refused
        case fullScreenTimeout
        case gone
        case retryable(Int32)
        case desktopChanged
        case restoreFailed
    }

    public struct Outcome: Sendable {
        public var applied: CGRect?
        public var failure: Failure?
        public var isExact: Bool
        public var centredOnly: Bool

        public var succeeded: Bool { failure == nil }

        public static func failed(_ failure: Failure) -> Outcome {
            Outcome(applied: nil, failure: failure, isExact: false, centredOnly: false)
        }
    }

    public static func standardWindows(of application: AXElement) -> [AXElement] {
        AX.elements(kAXWindowsAttribute, of: application).filter { isStandardWindow($0) }
    }

    public static func focusedWindow(of application: AXElement) -> AXElement? {
        if let focused = AX.element(kAXFocusedWindowAttribute, of: application), isStandardWindow(focused) {
            return focused
        }
        return standardWindows(of: application).first
    }

    public static func isStandardWindow(_ element: AXElement) -> Bool {
        guard AX.role(of: element) == kAXWindowRole else { return false }
        let subrole = AX.subrole(of: element)
        guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { return false }
        guard let size = AX.size(kAXSizeAttribute, of: element), size.width > 1, size.height > 1 else { return false }
        return true
    }

    public static func isFullScreen(_ window: AXElement) -> Bool {
        AX.bool(fullScreenAttribute, of: window) ?? false
    }

    @discardableResult
    public static func prepare(_ window: AXElement) -> Failure? {
        if AX.bool(kAXMinimizedAttribute, of: window) == true {
            guard AX.setBool(kAXMinimizedAttribute, false, on: window) == .success,
                  waitUntil(timeout: 0.5, condition: { AX.bool(kAXMinimizedAttribute, of: window) == false }) else { return .restoreFailed }
        }

        if isFullScreen(window) {
            AX.setBool(fullScreenAttribute, false, on: window)
            let left = waitUntil(timeout: 1.5) { !isFullScreen(window) }
            if !left { return .fullScreenTimeout }
            Thread.sleep(forTimeInterval: 0.25)
        }

        return nil
    }

    public static func place(_ window: AXElement, into target: CGRect, tolerance: CGFloat = 2,
                             validation: (@Sendable () -> Bool)? = nil) -> Outcome {
        guard validation?() != false else { return .failed(.desktopChanged) }
        guard AX.isTrusted else { return .failed(.notTrusted) }

        if let failure = prepare(window) { return .failed(failure) }
        guard validation?() != false else { return .failed(.desktopChanged) }

        guard AX.frame(of: window) != nil else { return .failed(.gone) }
        guard AX.isSettable(kAXPositionAttribute, on: window) else { return .failed(.positionNotSettable) }

        let wanted = Geo.integral(target)
        let workArea = DisplayRegistry.current.display(bestFor: wanted)?.workAreaAX ?? wanted
        let sizeSettable = AX.isSettable(kAXSizeAttribute, on: window)

        if !sizeSettable {
            guard let current = AX.frame(of: window) else { return .failed(.gone) }
            let centred = Geo.windowOrigin(CGPoint(x: wanted.midX - current.width / 2, y: wanted.midY - current.height / 2),
                                           actualSize: current.size, zone: wanted, workArea: workArea)
            guard validation?() != false else { return .failed(.desktopChanged) }
            let error = AX.setPosition(centred, on: window)
            if let failure = classify(error) { return .failed(failure) }
            let landed = AX.frame(of: window)
            return Outcome(applied: landed, failure: nil, isExact: false, centredOnly: true)
        }

        guard validation?() != false else { return .failed(.desktopChanged) }
        if let failure = classify(AX.setPosition(wanted.origin, on: window)) { return .failed(failure) }
        guard validation?() != false else { return .failed(.desktopChanged) }
        if let failure = classify(AX.setSize(wanted.size, on: window)) { return .failed(failure) }
        guard validation?() != false else { return .failed(.desktopChanged) }
        if let failure = classify(AX.setPosition(wanted.origin, on: window)) { return .failed(failure) }

        guard var landed = AX.frame(of: window) else { return .failed(.gone) }
        var requestedOrigin = wanted.origin

        if !Geo.matches(landed, wanted, tolerance: tolerance) {
            requestedOrigin = Geo.windowOrigin(wanted.origin, actualSize: landed.size, zone: wanted, workArea: workArea)
            guard validation?() != false else { return .failed(.desktopChanged) }
            if let failure = classify(AX.setPosition(requestedOrigin, on: window)) { return .failed(failure) }
            guard let second = AX.frame(of: window) else { return .failed(.gone) }
            landed = second
        }

        if Geo.matches(landed, wanted, tolerance: tolerance) {
            return Outcome(applied: landed, failure: nil, isExact: true, centredOnly: false)
        }

        let originDrift = max(abs(landed.minX - requestedOrigin.x), abs(landed.minY - requestedOrigin.y))
        if originDrift > tolerance {
            return Outcome(applied: landed, failure: .refused, isExact: false, centredOnly: false)
        }
        return Outcome(applied: landed, failure: nil, isExact: false, centredOnly: false)
    }

    public static func placeOnLaunch(_ resolve: () -> AXElement?, into target: CGRect) -> Outcome {
        guard let first = resolve() else { return .failed(.gone) }
        Thread.sleep(forTimeInterval: 0.4)
        var outcome = place(first, into: target)
        Thread.sleep(forTimeInterval: 0.5)
        guard let second = resolve() else { return outcome }
        let again = place(second, into: target)
        if again.isExact || outcome.failure != nil { outcome = again }
        return outcome
    }

    private static func classify(_ error: AXError) -> Failure? {
        switch error {
        case .success: return nil
        case .invalidUIElement, .invalidUIElementObserver: return .gone
        case .attributeUnsupported, .actionUnsupported: return .positionNotSettable
        default: return .retryable(error.rawValue)
        }
    }

    private static func waitUntil(timeout: TimeInterval, step: TimeInterval = 0.05, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: step)
        }
        return condition()
    }
}
