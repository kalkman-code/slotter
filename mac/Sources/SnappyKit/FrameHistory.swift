import AppKit

@MainActor
public final class FrameHistory {
    public static let shared = FrameHistory()

    private struct Entry {
        var pid: pid_t
        var frame: CGRect
        var stamp: Date
    }

    private var entries: [AXElement: Entry] = [:]
    private let capacity = 64

    public init() {}

    public func record(_ window: AXElement, pid: pid_t, frame: CGRect) {
        entries[window] = Entry(pid: pid, frame: frame, stamp: Date())
        trim()
    }

    public func swap(_ window: AXElement, pid: pid_t, current: CGRect) -> CGRect? {
        guard let previous = entries[window]?.frame else { return nil }
        entries[window] = Entry(pid: pid, frame: current, stamp: Date())
        return previous
    }

    public func purge(pid: pid_t) {
        entries = entries.filter { $0.value.pid != pid }
    }

    public func clampToDisplays(_ snapshot: DisplaySnapshot) {
        guard !snapshot.displays.isEmpty else { return }
        for (key, entry) in entries {
            let intersects = snapshot.displays.contains { !$0.frameAX.intersection(entry.frame).isNull }
            if intersects { continue }
            guard let fallback = snapshot.displays.first else { continue }
            entries[key]?.frame = Geo.clamp(entry.frame, into: fallback.workAreaAX)
        }
    }

    private func trim() {
        guard entries.count > capacity else { return }
        let ordered = entries.sorted { $0.value.stamp < $1.value.stamp }
        for (key, _) in ordered.prefix(entries.count - capacity) {
            entries.removeValue(forKey: key)
        }
    }
}
