import AppKit

public struct SnapTarget: Sendable, Identifiable, Equatable {
    public enum Source: Sendable, Equatable {
        case zone(index: Int)
        case edge(SnapAction)
    }

    public let id: Int
    public let source: Source
    public let hitRegion: CGRect
    public let frame: CGRect
    public let caption: String
    public let display: CGDirectDisplayID

    public var isEdge: Bool {
        if case .edge = source { return true }
        return false
    }
}

public enum SnapTargetBuilder {
    public static let bandThickness: CGFloat = 12
    public static let cornerSize: CGFloat = 80

    public static func build(workspace: Workspace?,
                             snapshot: DisplaySnapshot) -> (zones: [SnapTarget], edges: [SnapTarget]) {
        build(workspacesByDisplay: [:], fallback: workspace, snapshot: snapshot)
    }

    public static func build(workspacesByDisplay: [String: Workspace], fallback: Workspace?,
                             snapshot: DisplaySnapshot) -> (zones: [SnapTarget], edges: [SnapTarget]) {
        var zones: [SnapTarget] = []
        var identifier = 0

        for display in snapshot.displays {
            let workspace = workspacesByDisplay[display.uuid] ?? fallback
            guard let workspace else { continue }
            for (index, zone) in workspace.zones.enumerated() {
                guard DisplayRegistry.resolve(zone.monitor, in: snapshot)?.id == display.id,
                      let frame = ZoneGeometry.bounds(for: zone, in: snapshot) else { continue }
                let program = zone.program ?? ""
                zones.append(SnapTarget(
                    id: identifier,
                    source: .zone(index: index),
                    hitRegion: frame,
                    frame: frame,
                    caption: program.isEmpty
                        ? "Zone \(index + 1) · ready for any app"
                        : "Zone \(index + 1) · \(program)",
                    display: display.id))
                identifier += 1
            }
        }

        var edges: [SnapTarget] = []
        for display in snapshot.displays {
            for candidate in edgeTargets(for: display, startingAt: identifier) {
                let duplicate = zones.contains {
                    $0.display == candidate.display && Geo.matches($0.frame, candidate.frame, tolerance: 2)
                }
                guard !duplicate else { continue }
                edges.append(candidate)
                identifier += 1
            }
        }

        return (zones, edges)
    }

    public static func edgeTargets(for display: DisplayInfo, startingAt start: Int) -> [SnapTarget] {
        let screen = display.frameAX
        let work = display.workAreaAX
        let thickness = bandThickness
        let corner = min(cornerSize, min(screen.width, screen.height) / 4)

        var results: [SnapTarget] = []
        var identifier = start

        func add(_ action: SnapAction, _ hit: CGRect) {
            guard let frame = MagnetLayouts.frame(for: action, work: work, current: work) else { return }
            results.append(SnapTarget(id: identifier,
                                      source: .edge(action),
                                      hitRegion: hit,
                                      frame: frame,
                                      caption: action.title,
                                      display: display.id))
            identifier += 1
        }

        add(.topLeft, CGRect(x: screen.minX, y: screen.minY, width: corner, height: corner))
        add(.topRight, CGRect(x: screen.maxX - corner, y: screen.minY, width: corner, height: corner))
        add(.bottomLeft, CGRect(x: screen.minX, y: screen.maxY - corner, width: corner, height: corner))
        add(.bottomRight, CGRect(x: screen.maxX - corner, y: screen.maxY - corner, width: corner, height: corner))

        let verticalSpan = max(1, screen.height - corner * 2)
        add(.leftHalf, CGRect(x: screen.minX, y: screen.minY + corner, width: thickness, height: verticalSpan))
        add(.rightHalf, CGRect(x: screen.maxX - thickness, y: screen.minY + corner,
                               width: thickness, height: verticalSpan))

        let horizontalSpan = max(1, screen.width - corner * 2)
        add(.maximise, CGRect(x: screen.minX + corner, y: screen.minY, width: horizontalSpan, height: thickness))

        let third = horizontalSpan / 3
        for (index, action) in [SnapAction.leftThird, .centreThird, .rightThird].enumerated() {
            add(action, CGRect(x: screen.minX + corner + third * CGFloat(index),
                               y: screen.maxY - thickness,
                               width: third,
                               height: thickness))
        }

        return results
    }

    public static func hit(at point: CGPoint, zones: [SnapTarget], edges: [SnapTarget]) -> SnapTarget? {
        if let edge = edges.first(where: { $0.hitRegion.contains(point) }) { return edge }
        return zones.last { $0.hitRegion.contains(point) }
    }
}
