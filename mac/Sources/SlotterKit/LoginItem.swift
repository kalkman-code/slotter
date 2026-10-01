import AppKit
import ServiceManagement

@MainActor
public enum LoginItem {
    public enum State: Sendable, CustomStringConvertible {
        case enabled
        case disabled
        case requiresApproval
        case unavailable

        public var isOn: Bool { self == .enabled }

        public var description: String {
            switch self {
            case .enabled: return "enabled"
            case .disabled: return "not registered"
            case .requiresApproval: return "needs approval in System Settings"
            case .unavailable: return "unavailable"
            }
        }
    }

    public static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    @discardableResult
    public static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            Log.write("start at login set to \(enabled), status now \(state)")
            return true
        } catch {
            Log.error("start at login failed: \(error.localizedDescription)")
            return false
        }
    }

    public static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    public static func reconcile(wanted: Bool) -> Bool {
        let current = state
        Log.write("start at login: \(current), config wants \(wanted)")

        guard wanted, current == .disabled else { return current.isOn }
        Log.write("re-registering start at login — the record did not survive")
        return set(true)
    }
}
