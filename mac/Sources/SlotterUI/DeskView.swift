import AppKit
import SlotterKit
import SwiftUI

private let P = T.palette

/// The desk: every monitor drawn as an object at its physical size, standing on one desk line,
/// with the selected workspace's zones on its screen.
struct DeskView: View {
    @Bindable var model: SettingsModel
    let layout: DesignerLayout

    var body: some View {
        GeometryReader { proxy in
            let desk = model.desk
            let workspace = model.selectedWorkspace
            let stageTop: CGFloat = layout.narrow ? 24 : 84
            let stage = CGSize(width: proxy.size.width, height: max(0, proxy.size.height - stageTop))
            let frame = StageFrame(desk: desk, size: stage, narrow: layout.narrow,
                                   sinkToDesk: workspace == nil && layout.narrow)

            ZStack(alignment: .topLeading) {
                Stage(model: model, desk: desk, frame: frame, workspace: workspace, narrow: layout.narrow)
                    .frame(width: stage.width, height: stage.height, alignment: .topLeading)
                    .offset(y: stageTop)

                DocumentHead(model: model, desk: desk, workspace: workspace, narrow: layout.narrow)

                if workspace == nil && layout.narrow {
                    FirstRunNote(model: model, heading: T.type.heading)
                        .frame(maxWidth: 520, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.top, 30)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .overlay(alignment: .topTrailing) {
                // On the plates' line, whichever glyph it leads with, so it reads as one row.
                // Dropped rather than crowding the last plate, and while the settings tab that says the
                // same is open.
                let plateRight = desk.placements.last.map { frame.originX + $0.centreX * frame.scale + Plate.width($0.monitor) / 2 } ?? 0
                if !layout.narrow, model.face != .settings, plateRight + 24 < proxy.size.width - 28 - MarginNote.width(model.status) {
                    MarginNote(model: model)
                        .padding(.trailing, 28)
                        .offset(y: stageTop + frame.deskY + 8 - 4)
                }
            }
        }
        .background(LinearGradient(colors: [P.ground, P.groundLow], startPoint: .top, endPoint: .bottom))
        .clipped()
        .onMoveCommand { direction in
            model.moveZoneSelection(by: direction == .left || direction == .up ? -1 : 1)
        }
    }
}

/// One scale factor times inch measurements, fitted to the stage as the mock does.
struct StageFrame {
    let scale: CGFloat
    let originX: CGFloat
    let originY: CGFloat
    let deskY: CGFloat
    let captionHeight: CGFloat

    init(desk: DeskArrangement, size: CGSize, narrow: Bool, sinkToDesk: Bool) {
        captionHeight = narrow ? 34 : 42
        let pad: CGFloat = narrow ? 12 : 32
        scale = max(2, min((size.width - pad * 2) / desk.width, (size.height - captionHeight - 10) / desk.deskLine))
        originX = (size.width - desk.width * scale) / 2
        let free = size.height - captionHeight - desk.deskLine * scale
        originY = max(4, free - max(0, free * (sinkToDesk ? 0 : 0.35)))
        deskY = originY + desk.deskLine * scale
    }
}

private struct Stage: View {
    let model: SettingsModel
    let desk: DeskArrangement
    let frame: StageFrame
    let workspace: Workspace?
    let narrow: Bool

    var body: some View {
        let s = frame.scale
        let firstRunHost = workspace == nil && !narrow
            ? desk.placements.filter(\.monitor.isConnected).max { $0.screenWidth * $0.screenHeight < $1.screenWidth * $1.screenHeight }?.monitor.id
            : nil
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [P.desk, P.deskLow], startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .top) { Rectangle().fill(P.deskEdge).frame(height: 1) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, frame.deskY)

            ForEach(desk.placements, id: \.monitor.id) { placement in
                let bezel = max(3, placement.bezel * s)
                let chin = max(5, placement.chin * s)
                let screen = CGSize(width: placement.screenWidth * s, height: placement.screenHeight * s)
                let outer = CGSize(width: screen.width + bezel * 2, height: screen.height + bezel + chin)
                let left = frame.originX + placement.x * s
                let top = frame.originY + placement.y * s
                let centre = left + outer.width / 2
                let footHeight = max(4, placement.footHeight * s)
                let neckWidth = max(8, placement.neckWidth * s)
                let footWidth = placement.footWidth * s
                let hasFault = workspace?.zones.contains { model.monitorKey($0) == placement.monitor.id && model.fault(of: $0) != nil } ?? false

                ZStack(alignment: .topLeading) {
                    LinearGradient(stops: [.init(color: P.standLow, location: 0), .init(color: P.standHigh, location: 0.45),
                                           .init(color: P.standLow, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: neckWidth, height: max(0, frame.deskY - footHeight - (top + outer.height)))
                        .offset(x: centre - neckWidth / 2, y: top + outer.height)

                    UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 4)
                        .fill(LinearGradient(colors: [P.standHigh, P.stand], startPoint: .top, endPoint: .bottom))
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 4)
                            .strokeBorder(P.standEdge, lineWidth: 1))
                        .frame(width: footWidth, height: footHeight)
                        .offset(x: centre - footWidth / 2, y: frame.deskY - footHeight)

                    MonitorView(model: model, placement: placement, workspace: workspace, screen: screen,
                                bezel: bezel, outer: outer, narrow: narrow,
                                showsFirstRun: placement.monitor.id == firstRunHost)
                        .offset(x: left, y: top)

                    Plate(monitor: placement.monitor)
                        .frame(width: 260)
                        .offset(x: centre - 130, y: frame.deskY + (narrow ? 4 : 8))
                }
                .zIndex(hasFault ? 2 : 0)
            }
        }
    }
}

private struct MonitorView: View {
    let model: SettingsModel
    let placement: DeskPlacement
    let workspace: Workspace?
    let screen: CGSize
    let bezel: CGFloat
    let outer: CGSize
    let narrow: Bool
    let showsFirstRun: Bool

    var body: some View {
        let monitor = placement.monitor
        let off = !monitor.isConnected
        let zones = workspace?.zones.filter { model.monitorKey($0) == monitor.id } ?? []
        let unused = workspace != nil && zones.isEmpty
        let shape = RoundedRectangle(cornerRadius: T.radii.bezel)

        ZStack(alignment: .topLeading) {
            Group {
                if off {
                    shape.fill(P.bezel).dashedBorder(P.bezelEdge, radius: T.radii.bezel)
                } else {
                    shape.fill(LinearGradient(stops: [.init(color: P.bezelTop, location: 0), .init(color: P.bezel, location: 0.18)],
                                              startPoint: .top, endPoint: .bottom))
                        .overlay(shape.strokeBorder(P.bezelEdge, lineWidth: 1))
                }
            }
            .frame(width: outer.width, height: outer.height)

            ZStack(alignment: .topLeading) {
                screenFill(off: off, unused: unused)
                    .frame(width: screen.width, height: screen.height)

                if let workspace {
                    ForEach(zones) { zone in
                        ZoneView(model: model, zone: zone, number: model.number(of: zone, in: workspace),
                                 screen: screen, offline: off)
                    }
                    if unused {
                        VStack(spacing: 6) {
                            Text("Not used by \(workspace.name)")
                                .font(T.font(T.type.small))
                                .foregroundStyle(P.ink3)
                                .multilineTextAlignment(.center)
                            LinkButton(title: "Use this monitor") { model.useMonitor(monitor) }
                        }
                        .padding(8)
                        .frame(width: screen.width, height: screen.height)
                    }
                } else if showsFirstRun {
                    FirstRunNote(model: model, heading: T.type.zoneNote, centred: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(width: screen.width, height: screen.height)
                }

                if off && !narrow {
                    Text("DISCONNECTED")
                        .font(T.font(T.type.caption, .bold))
                        .tracking(0.5)
                        .foregroundStyle(P.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: T.radii.chip).fill(P.pill))
                        .dashedBorder(P.ink2, radius: T.radii.chip)
                        .fixedSize()
                        .frame(width: screen.width)
                        .offset(y: -10)
                }
            }
            .offset(x: bezel - 1, y: bezel - 1)
        }
        .frame(width: outer.width, height: outer.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func screenFill(off: Bool, unused: Bool) -> some View {
        if off {
            Rectangle().fill(P.screenOff)
        } else if unused {
            Rectangle().fill(P.screenUnused)
        } else {
            Rectangle().fill(LinearGradient(stops: [.init(color: P.screenTop, location: 0), .init(color: P.screen, location: 0.6)],
                                            startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1)))
        }
    }
}

private struct ZoneView: View {
    let model: SettingsModel
    let zone: Zone
    let number: Int
    let screen: CGSize
    let offline: Bool
    @State private var hovering = false

    var body: some View {
        let program = model.program(named: zone.program)
        let fault = model.fault(of: zone)
        let selected = zone.id == model.selectedZoneID
        let width = max(0, screen.width * zone.w / 100 - 4)
        let height = max(0, screen.height * zone.h / 100 - 4)
        // The selected zone keeps the large treatment down to 100pt, so at 640 the zone being
        // edited still reads. A zone too short for chip over name puts them on one line.
        let big = selected && width >= 100
        let size: CGFloat = width > 150 && height > 120 ? 17 : (width > 110 || big) ? 15 : 13
        let name = program?.name ?? (zone.program.map { $0 } ?? "Empty")
        let tiny = (width < 110 && !big) || height < 56
        let inline = height < 57
        let nameWidth = CGFloat(name.count) * size * 0.6
        let micro = height < 24 || (inline ? 22 + 6 + nameWidth + 16 > width : nameWidth + 18 > width)
        let note = faultText(fault) ?? program.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "Drop target"
        let chip = Text("\(number)")
            .font(T.font(T.type.body, .extraBold).monospacedDigit())
            .foregroundStyle(selected ? P.onSelection : P.ink)
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: T.radii.chip).fill(selected ? P.selection : P.zoneChip))
        let title = Text(name)
            .font(T.font(size, program == nil ? .semibold : .bold))
            .foregroundStyle(program == nil ? P.ink2 : P.ink)
            .lineLimit(1)
            .fixedSize()

        Button { model.selectZone(zone.id) } label: {
            Group {
                if inline {
                    HStack(spacing: 6) {
                        chip
                        if !micro { title }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        chip
                        if !micro { title }
                        if !tiny {
                            Text(note)
                                .font(T.font(T.type.label, fault == nil ? .regular : .semibold))
                                .foregroundStyle(fault == nil ? P.ink2 : P.error)
                                .lineLimit(fault == nil ? 1 : 3)
                                .truncationMode(.middle)
                                .frame(maxWidth: max(0, min(260, width - 16)), alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, tiny ? 4 : 8)
            .padding(.vertical, inline ? max(0, min(7, (height - 22) / 2)) : tiny ? 4 : 7)
            .frame(width: width, height: height, alignment: .topLeading)
            .clipped(antialiased: false)
            .background(RoundedRectangle(cornerRadius: T.radii.chip).fill(fill(program: program, fault: fault)))
            .overlay { border(program: program, fault: fault, selected: selected) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .focusRing(radius: T.radii.chip)
        .offset(x: screen.width * zone.x / 100 + 2, y: screen.height * zone.y / 100 + 2)
        .accessibilityLabel("Zone \(number), \(program?.name ?? "empty")\(fault == nil ? "" : ", fault: \(note)")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func faultText(_ fault: SettingsModel.ZoneFault?) -> String? {
        switch fault {
        case .none: nil
        case .empty: "Width and Height must be more than 0%."
        case .negative: "Left and Top cannot be below 0%."
        case let .pastRight(over): "Runs \(Percent.text(over))% past the right edge"
        case let .pastBottom(over): "Runs \(Percent.text(over))% past the bottom edge"
        }
    }

    private func fill(program: Program?, fault: SettingsModel.ZoneFault?) -> Color {
        if fault != nil { return P.faultGround }
        if offline { return .clear }
        return program == nil ? P.zoneEmpty : P.zone
    }

    @ViewBuilder
    private func border(program: Program?, fault: SettingsModel.ZoneFault?, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: T.radii.chip)
        if fault != nil {
            shape.strokeBorder(P.error, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            if selected { shape.strokeBorder(P.selection, lineWidth: 2).padding(2) }
        } else if selected {
            shape.strokeBorder(P.selection, lineWidth: 2)
        } else if offline {
            shape.strokeBorder(P.zoneOfflineLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else if program == nil {
            shape.strokeBorder(hovering ? P.zoneHover : P.zoneEmptyLine, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        } else {
            shape.strokeBorder(hovering ? P.zoneHover : P.zoneLine, lineWidth: 1)
        }
    }
}

private struct Plate: View {
    let monitor: DeskMonitor

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Text(monitor.name).font(T.font(T.type.body, .bold)).foregroundStyle(P.ink)
                if !monitor.isConnected { Tag("Disconnected") }
            }
            Text(detail)
                .font(T.font(T.type.label).monospacedDigit())
                .foregroundStyle(P.ink2)
        }
        .lineLimit(1)
        .multilineTextAlignment(.center)
    }

    static func width(_ monitor: DeskMonitor) -> CGFloat {
        max(measure(monitor.name, T.nsFont(T.type.body, .bold)) + (monitor.isConnected ? 0 : 90),
            measure(detail(monitor), T.nsFont(T.type.label)))
    }

    private var detail: String { Self.detail(monitor) }

    private static func detail(_ monitor: DeskMonitor) -> String {
        var parts: [String] = []
        if !monitor.resolutionLabel.isEmpty { parts.append(monitor.resolutionLabel) }
        if let diagonal = monitor.diagonalInches { parts.append("\(Int(diagonal.rounded())) in") }
        if !monitor.isConnected && parts.isEmpty { parts.append("Last seen size unknown") }
        return parts.joined(separator: " · ")
    }
}

private struct FirstRunNote: View {
    let model: SettingsModel
    let heading: CGFloat
    var centred = false

    var body: some View {
        VStack(alignment: centred ? .center : .leading, spacing: 8) {
            Text("Make your first workspace")
                .font(T.font(heading, .bold))
                .tracking(-0.2)
                .foregroundStyle(P.ink)
            Text("A workspace is a named set of apps, each opened into a zone on one of these monitors. "
                + (model.snapshot.displays.count == 1 ? "It is connected and ready." : model.snapshot.displays.count == 2 ? "Both are connected and ready." : "They are connected and ready."))
                .font(T.font(T.type.small))
                .foregroundStyle(P.ink2)
                .multilineTextAlignment(centred ? .center : .leading)
                .frame(maxWidth: centred ? 360 : 520, alignment: centred ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("New workspace") { model.addWorkspace() }.buttonStyle(InkButtonStyle(kind: .primary))
                Button("Add programs first") { model.showingPrograms = true }.buttonStyle(InkButtonStyle(kind: .secondary))
            }
        }
    }
}

private struct DocumentHead: View {
    let model: SettingsModel
    let desk: DeskArrangement
    let workspace: Workspace?
    let narrow: Bool

    var body: some View {
        let meta = metaLine
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                if !narrow {
                    Text(workspace?.name ?? "No workspaces yet")
                        .font(T.font(T.type.title, .display))
                        .tracking(-0.64)
                        .foregroundStyle(P.ink)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(narrow ? meta.short : meta.long)
                    .font(T.font(narrow ? T.type.small : T.type.body))
                    .foregroundStyle(meta.bad ? P.error : P.ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !narrow {
                Text(aside)
                    .font(T.font(T.type.small))
                    .foregroundStyle(P.ink3)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 260, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, narrow ? 14 : 32)
        .padding(.top, narrow ? 6 : 16)
    }

    private var metaLine: (long: String, short: String, bad: Bool) {
        let names = { (keys: [String]) in
            keys.compactMap { key in desk.monitors.first { $0.id == key }?.name }
        }
        guard let workspace else {
            let connected = desk.monitors.filter(\.isConnected).map(\.name)
            let count = Self.countWord(connected.count, "monitor")
            return ("First run. \(count) found: \(Self.list(connected)).", "First run. \(count) found.", false)
        }
        let keys = model.monitorKeys(of: workspace, in: desk)
        let gone = names(keys.filter(model.isOffline))
        if !gone.isEmpty {
            let one = gone.count == 1
            return ("\(Self.list(gone)) \(one ? "is" : "are") disconnected. \(one ? "Its" : "Their") zones stay editable and fill when \(one ? "it returns" : "they return").",
                    "\(Self.list(gone)) disconnected. Edits are kept.", true)
        }
        let apps = workspace.zones.filter { !($0.program ?? "").isEmpty }.count
        let zones = workspace.zones.count == 1 ? "1 zone" : "\(workspace.zones.count) zones"
        let counts = "\(zones), \(apps) with apps"
        let used = names(keys)
        return ((used.isEmpty ? "" : used.joined(separator: " + ") + " · ") + counts,
                counts + (desk.trueScale ? " · drawn at true size" : " · drawn in proportion"), false)
    }

    private var aside: String {
        guard desk.trueScale else {
            return "Drawn in proportion: no monitor reported its physical size."
        }
        let sized = desk.monitors.compactMap { monitor in
            monitor.diagonalInches.map { "the \(Int($0.rounded())) in \(monitor.name)" }
        }
        return "Drawn at true size: \(Self.list(sized)) as \(sized.count == 1 ? "it stands" : "they stand") on the desk."
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    static func countWord(_ count: Int, _ noun: String) -> String {
        let words = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"]
        let word = count < words.count ? words[count] : "\(count)"
        return "\(word) \(noun)\(count == 1 ? "" : "s")"
    }
}

private struct MarginNote: View {
    let model: SettingsModel

    static func text(_ status: SettingsModel.Status) -> String {
        !status.accessibilityTrusted ? "Accessibility not granted"
            : status.shortcutFailures > 0 ? "\(status.shortcutFailures) snap shortcut\(status.shortcutFailures == 1 ? "" : "s") unavailable"
            : "Snap shortcuts ready"
    }

    static func width(_ status: SettingsModel.Status) -> CGFloat {
        let bad = !status.accessibilityTrusted || status.shortcutFailures > 0
        return measure(text(status), T.nsFont(T.type.small, bad ? .semibold : .regular)) + (bad ? 18 : 0) + 12
    }

    var body: some View {
        let status = model.status
        let bad = !status.accessibilityTrusted || status.shortcutFailures > 0
        let text = Self.text(status)
        Button { model.face = .settings } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if bad { Icon(kind: .warn, size: 12).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 } }
                Text(text).font(T.font(T.type.small, bad ? .semibold : .regular))
            }
            .foregroundStyle(bad ? P.error : P.ink3)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusRing()
    }
}

/// The one percentage format, for fields and sentences alike: one decimal, trailing zero trimmed.
/// Storage keeps two decimals.
func measure(_ text: String, _ font: NSFont) -> CGFloat {
    (text as NSString).size(withAttributes: [.font: font]).width
}

enum Percent {
    static func text(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}
