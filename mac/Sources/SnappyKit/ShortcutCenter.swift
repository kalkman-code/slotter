import AppKit
import Carbon.HIToolbox

@MainActor
public final class ShortcutCenter {
    public static let shared = ShortcutCenter()

    public struct Registration: Sendable {
        public var action: SnapAction
        public var combo: KeyCombo
        public var status: OSStatus

        public var succeeded: Bool { status == noErr }

        public var title: String {
            succeeded
                ? "\(combo.display)   \(action.title)"
                : "\(combo.display)   \(action.title) — unavailable"
        }
    }

    private var handler: EventHandlerRef?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: SnapAction] = [:]
    private var nextID: UInt32 = 1

    public var onAction: ((SnapAction) -> Void)?

    public init() {}

    @discardableResult
    public func register(_ table: [SnapAction: KeyCombo]) -> [Registration] {
        unregisterAll()
        installHandler()

        var results: [Registration] = []
        for action in SnapAction.allCases {
            guard let combo = table[action] else { continue }
            let id = nextID
            nextID += 1

            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x536E_7079), id: id)
            let status = RegisterEventHotKey(combo.keyCode,
                                             combo.modifiers,
                                             hotKeyID,
                                             GetEventDispatcherTarget(),
                                             0,
                                             &ref)
            if status == noErr, let ref {
                refs[id] = ref
                actions[id] = action
            }
            results.append(Registration(action: action, combo: combo, status: status))
        }

        let failed = results.filter { !$0.succeeded }
        if failed.isEmpty {
            Log.write("shortcuts registered: \(results.count)")
        } else {
            for failure in failed {
                Log.error("shortcut unavailable: \(failure.action.title) \(failure.combo.display) status=\(failure.status)")
            }
        }
        return results
    }

    public func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        actions.removeAll()
    }

    fileprivate func fire(id: UInt32) {
        guard let action = actions[id] else { return }
        onAction?(action)
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), shortcutEventHandler, 1, &spec, nil, &handler)
    }
}

private let shortcutEventHandler: EventHandlerUPP = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr else { return status }
    let id = hotKeyID.id
    MainActor.assumeIsolated {
        ShortcutCenter.shared.fire(id: id)
    }
    return noErr
}
