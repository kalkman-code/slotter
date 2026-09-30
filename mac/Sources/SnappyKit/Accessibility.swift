import AppKit
import ApplicationServices

public struct AXElement: Hashable, @unchecked Sendable {
    public let ref: AXUIElement

    public init(_ ref: AXUIElement) { self.ref = ref }

    public static func == (lhs: AXElement, rhs: AXElement) -> Bool { CFEqual(lhs.ref, rhs.ref) }
    public func hash(into hasher: inout Hasher) { hasher.combine(CFHash(ref)) }
}

public enum AX {
    public static let queue = DispatchQueue(label: "com.tobykalkman.snappy.ax", qos: .userInitiated)

    public static let messagingTimeout: Float = 0.25

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    public static func requestTrust() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    public static func perform<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: body()) }
        }
    }

    public static func application(pid: pid_t) -> AXElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return AXElement(element)
    }

    public static func systemWide() -> AXElement {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, 0.20)
        return AXElement(element)
    }

    public static func element(at point: CGPoint) -> AXElement? {
        var found: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(systemWide().ref, Float(point.x), Float(point.y), &found)
        guard status == .success, let found else { return nil }
        AXUIElementSetMessagingTimeout(found, messagingTimeout)
        return AXElement(found)
    }

    public static func value(_ attribute: String, of element: AXElement) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element.ref, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    public static func elements(_ attribute: String, of element: AXElement) -> [AXElement] {
        guard let raw = value(attribute, of: element), let array = raw as? [AXUIElement] else { return [] }
        return array.map {
            AXUIElementSetMessagingTimeout($0, messagingTimeout)
            return AXElement($0)
        }
    }

    public static func element(_ attribute: String, of element: AXElement) -> AXElement? {
        guard let raw = value(attribute, of: element), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let child = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(child, messagingTimeout)
        return AXElement(child)
    }

    public static func string(_ attribute: String, of element: AXElement) -> String? {
        value(attribute, of: element) as? String
    }

    public static func bool(_ attribute: String, of element: AXElement) -> Bool? {
        value(attribute, of: element) as? Bool
    }

    public static func role(of element: AXElement) -> String? { string(kAXRoleAttribute, of: element) }
    public static func subrole(of element: AXElement) -> String? { string(kAXSubroleAttribute, of: element) }
    public static func title(of element: AXElement) -> String? { string(kAXTitleAttribute, of: element) }

    public static func pid(of element: AXElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element.ref, &pid) == .success else { return nil }
        return pid
    }

    public static func point(_ attribute: String, of element: AXElement) -> CGPoint? {
        guard let raw = value(attribute, of: element), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var result = CGPoint.zero
        guard AXValueGetValue(raw as! AXValue, .cgPoint, &result) else { return nil }
        return result
    }

    public static func size(_ attribute: String, of element: AXElement) -> CGSize? {
        guard let raw = value(attribute, of: element), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var result = CGSize.zero
        guard AXValueGetValue(raw as! AXValue, .cgSize, &result) else { return nil }
        return result
    }

    public static func frame(of element: AXElement) -> CGRect? {
        guard let origin = point(kAXPositionAttribute, of: element),
              let extent = size(kAXSizeAttribute, of: element) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    @discardableResult
    public static func setPosition(_ origin: CGPoint, on element: AXElement) -> AXError {
        var mutable = origin
        guard let boxed = AXValueCreate(.cgPoint, &mutable) else { return .failure }
        return AXUIElementSetAttributeValue(element.ref, kAXPositionAttribute as CFString, boxed)
    }

    @discardableResult
    public static func setSize(_ extent: CGSize, on element: AXElement) -> AXError {
        var mutable = extent
        guard let boxed = AXValueCreate(.cgSize, &mutable) else { return .failure }
        return AXUIElementSetAttributeValue(element.ref, kAXSizeAttribute as CFString, boxed)
    }

    @discardableResult
    public static func setBool(_ attribute: String, _ flag: Bool, on element: AXElement) -> AXError {
        AXUIElementSetAttributeValue(element.ref, attribute as CFString, flag as CFBoolean)
    }

    public static func isSettable(_ attribute: String, on element: AXElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element.ref, attribute as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }

    public static func performAction(_ action: String, on element: AXElement) -> AXError {
        AXUIElementPerformAction(element.ref, action as CFString)
    }
}
