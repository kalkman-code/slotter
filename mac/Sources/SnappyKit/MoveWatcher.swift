import AppKit
import ApplicationServices

@MainActor
public final class MoveWatcher {
    public var onMoved: ((AXElement) -> Void)?
    public var onResized: ((AXElement) -> Void)?

    private var observer: AXObserver?
    private var application: AXElement?

    public init() {}

    public func watch(pid: pid_t) {
        stop()

        var created: AXObserver?
        guard AXObserverCreate(pid, moveWatcherCallback, &created) == .success, let created else { return }

        let element = AX.application(pid: pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, element.ref, kAXWindowMovedNotification as CFString, context)
        AXObserverAddNotification(created, element.ref, kAXWindowResizedNotification as CFString, context)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)

        observer = created
        application = element
    }

    public func stop() {
        guard let observer, let application else { return }
        AXObserverRemoveNotification(observer, application.ref, kAXWindowMovedNotification as CFString)
        AXObserverRemoveNotification(observer, application.ref, kAXWindowResizedNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = nil
        self.application = nil
    }

    fileprivate func deliver(notification: String, element: AXElement) {
        if notification == kAXWindowMovedNotification as String {
            onMoved?(element)
        } else if notification == kAXWindowResizedNotification as String {
            onResized?(element)
        }
    }
}

private func moveWatcherCallback(observer: AXObserver,
                                 element: AXUIElement,
                                 notification: CFString,
                                 refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let watcher = Unmanaged<MoveWatcher>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    let wrapped = AXElement(element)
    MainActor.assumeIsolated {
        watcher.deliver(notification: name, element: wrapped)
    }
}
