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
            let pinned = workspace?.virtualPlates.filter { $0.desktopID != nil } ?? []
            let reference = desk.placements.first
            let gap = desk.placements.dropFirst().first.map {
                CGFloat($0.x - (desk.placements.first?.x ?? 0) - (desk.placements.first?.outerWidth ?? 0))
            } ?? max(2, CGFloat(reference?.screenWidth ?? 120) * 0.09)
            let virtualWidth = pinned.reduce(CGFloat(0)) { total, plate in
                let placement = desk.placement(for: model.monitorKeyFor(plate.monitor)) ?? reference
                return total + CGFloat(placement?.outerWidth ?? 0) + gap
            }
            let ghostWidth = CGFloat(reference?.outerWidth ?? 0) + gap
            let stageTop: CGFloat = layout.narrow ? 24 : 84
            let stage = CGSize(width: proxy.size.width, height: max(0, proxy.size.height - stageTop))
            let shelfHeight = VirtualPlateShelf.height(for: workspace)
            let frame = StageFrame(desk: desk, size: stage, narrow: layout.narrow,
                                   sinkToDesk: workspace == nil && layout.narrow,
                                   extraWidth: workspace == nil ? 0 : virtualWidth + ghostWidth,
                                   reservedHeight: shelfHeight)

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
            .overlay(alignment: .bottomLeading) {
                if workspace != nil {
                    VirtualPlateShelf(model: model, desk: desk, physicalScale: frame.scale, maxHeight: shelfHeight)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 8)
                }
            }
        }
        .background(LinearGradient(colors: [P.ground, P.groundLow], startPoint: .top, endPoint: .bottom))
        .clipped()
        .onChange(of: model.showingVirtualChoices) { _, showing in
            if showing { model.status.spaceSnapshot = SpaceRegistry.shared.snapshot() }
        }
        .onMoveCommand { direction in
            model.moveZoneSelection(by: direction == .left || direction == .up ? -1 : 1)
        }
    }
}

private struct VirtualPlateShelf: View {
    @Bindable var model: SettingsModel
    let desk: DeskArrangement
    let physicalScale: CGFloat
    let maxHeight: CGFloat

    static func height(for workspace: Workspace?) -> CGFloat {
        guard let workspace else { return 0 }
        let bench = workspace.virtualPlates.contains { $0.desktopID == nil }
        return bench ? 66 : 0
    }

    var body: some View {
        let workspace = model.selectedWorkspace
        ScrollView(.vertical) {
          VStack(alignment: .leading, spacing: 4) {
            let benched = workspace?.virtualPlates.filter { $0.desktopID == nil } ?? []
            if let workspace, !benched.isEmpty {
                WrapLayout(spacing: 8, lineSpacing: 6) {
                    Text("BENCH").font(T.font(T.type.caption, .bold)).tracking(0.5).foregroundStyle(P.ink3)
                    ForEach(benched) { plate in
                        if let placement = desk.placements.first(where: { $0.monitor.id == model.monitorKeyFor(plate.monitor) }) {
                            let scale = physicalScale * 0.22
                            BenchedPlateThumbnail(model: model, plate: plate, workspace: workspace,
                                                 screen: CGSize(width: placement.screenWidth * scale, height: placement.screenHeight * scale))
                        }
                    }
                }
            }
          }
          .padding(8)
          .background(P.drawer.opacity(0.94))
          .overlay(alignment: .top) { Rectangle().fill(P.rule).frame(height: 1) }
        }
        .frame(maxHeight: maxHeight)
        .scrollIndicators(.hidden)
    }
}

private struct VirtualPlateMini: View {
    @Bindable var model: SettingsModel
    let plate: VirtualPlate
    let workspace: Workspace
    let placement: DeskPlacement
    let physicalScale: CGFloat

    private var zones: [Zone] { workspace.zones.filter { $0.plateID == plate.id } }
    private var desktopName: String {
        guard let id = plate.desktopID else { return "SAVED DESKTOP" }
        return model.status.spaceSnapshot.displays.flatMap(\.spaces).first { $0.uuid == id }?.label ?? "SAVED DESKTOP"
    }
    private var screen: CGSize {
        let scale = physicalScale * 0.4
        return CGSize(width: placement.screenWidth * scale, height: placement.screenHeight * scale)
    }
    private var selected: Bool { model.selectedVirtualPlateID == plate.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(desktopName)
                    .font(T.font(T.type.caption, .bold)).tracking(0.35).foregroundStyle(P.ink2)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(P.drawerFace).dashedBorder(P.rule, radius: T.radii.chip)
                Button(plate.name) { model.selectVirtualPlate(plate.id) }
                    .font(T.font(T.type.small, .semibold)).foregroundStyle(P.ink)
                    .lineLimit(1).buttonStyle(.plain)
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        model.selectVirtualPlate(plate.id)
                        model.focusVirtualPlateName = true
                    })
                    .help("Double-click to rename this plate")
                Spacer(minLength: 2)
                Button { model.benchVirtualPlate(plate.id) } label: {
                    HStack(spacing: 4) { Icon(kind: .tray, size: 11); Text("Bench") }
                }
                .buttonStyle(InkButtonStyle(kind: .quiet, height: 22))
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: T.radii.bezel).fill(P.bezel)
                ForEach(zones) { zone in
                    MiniPlateZone(model: model, zone: zone, number: model.number(of: zone, in: workspace), screen: screen)
                }
            }
            .padding(4)
            .frame(width: screen.width + 8, height: screen.height + 8)
            .overlay(RoundedRectangle(cornerRadius: T.radii.bezel)
                .strokeBorder(selected ? P.selection : P.ink2, style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: selected ? [] : [5, 3])))
            .contentShape(Rectangle())
        }
        .padding(6)
        .background(P.drawerFace)
        .dashedBorder(selected ? P.selection : P.rule, radius: T.radii.field)
    }
}

private struct MiniPlateZone: View {
    let model: SettingsModel
    let zone: Zone
    let number: Int
    let screen: CGSize

    var body: some View {
        Button { model.selectZone(zone.id) } label: {
            RoundedRectangle(cornerRadius: 2)
                .fill(zone.program == nil ? P.zoneEmpty : P.zone)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(zone.id == model.selectedZoneID ? P.selection : P.zoneLine, lineWidth: zone.id == model.selectedZoneID ? 2 : 1))
                .overlay(Text("\(number)").font(T.font(T.type.caption, .bold).monospacedDigit()).foregroundStyle(P.ink))
                .frame(width: max(2, screen.width * zone.w / 100 - 2), height: max(2, screen.height * zone.h / 100 - 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: screen.width * zone.x / 100 + 1, y: screen.height * zone.y / 100 + 1)
        .accessibilityLabel("Zone \(number)")
    }
}

private struct BenchedPlateThumbnail: View {
    @Bindable var model: SettingsModel
    let plate: VirtualPlate
    let workspace: Workspace
    let screen: CGSize
    private var zones: [Zone] { workspace.zones.filter { $0.plateID == plate.id } }

    var body: some View {
        HStack(spacing: 3) {
            Button {
                model.selectedBenchedPlateID = plate.id
                model.showingVirtualChoices = true
                model.selectedVirtualMonitorID = nil
            } label: {
                VStack(spacing: 2) {
                    GeometryReader { proxy in
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 3).fill(P.bezel)
                            ForEach(zones) { zone in
                                RoundedRectangle(cornerRadius: 1).fill(zone.program == nil ? P.zoneEmpty : P.zone)
                                    .overlay(RoundedRectangle(cornerRadius: 1).strokeBorder(P.zoneLine, lineWidth: 0.5))
                                    .frame(width: max(2, proxy.size.width * zone.w / 100 - 2), height: max(2, proxy.size.height * zone.h / 100 - 2))
                                    .offset(x: proxy.size.width * zone.x / 100 + 1, y: proxy.size.height * zone.y / 100 + 1)
                            }
                        }
                    }
                    .frame(width: screen.width, height: screen.height)
                    Text(plate.name).font(T.font(T.type.caption, .semibold)).foregroundStyle(P.ink2).lineLimit(1)
                    if let closed = plate.closedDesktopLabel {
                        Text("Closed \(closed)").font(T.font(T.type.caption)).foregroundStyle(P.ink3).lineLimit(1)
                    }
                }
                .frame(width: max(128, screen.width + 10), height: max(48, screen.height + 16))
                .help("Pull \(plate.name) out and choose a desktop")
            }
            .buttonStyle(.plain)
            Button { model.confirmDeleteBenchedPlate(plate.id) } label: { Icon(kind: .delete, size: 12) }
                .buttonStyle(IconButtonStyle(danger: true))
                .help("Delete benched plate")
                .accessibilityLabel("Delete \(plate.name)")
        }
        .padding(3)
        .background(P.drawerFace)
        .dashedBorder(P.rule, radius: T.radii.chip)
    }
}

/// One scale factor times inch measurements, fitted to the stage as the mock does.
struct StageFrame {
    let scale: CGFloat
    let originX: CGFloat
    let originY: CGFloat
    let deskY: CGFloat
    let captionHeight: CGFloat

    init(desk: DeskArrangement, size: CGSize, narrow: Bool, sinkToDesk: Bool, extraWidth: CGFloat = 0, reservedHeight: CGFloat = 0) {
        captionHeight = narrow ? 84 : 88
        let pad: CGFloat = narrow ? 12 : 32
        let deskHeight = max(0, size.height - reservedHeight)
        scale = max(reservedHeight > 0 ? 0.1 : 2,
                    min((size.width - pad * 2) / (desk.width + extraWidth), (deskHeight - captionHeight - 10) / desk.deskLine))
        originX = (size.width - (desk.width + extraWidth) * scale) / 2
        let free = deskHeight - captionHeight - desk.deskLine * scale
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
        let plateGap = desk.placements.dropFirst().first.map {
            CGFloat($0.x - (desk.placements.first?.x ?? 0) - (desk.placements.first?.outerWidth ?? 0))
        } ?? max(2, CGFloat(desk.placements.first?.screenWidth ?? 120) * 0.09)
        let firstRunHost = workspace == nil && !narrow
            ? desk.placements.filter(\.monitor.isConnected).max { $0.screenWidth * $0.screenHeight < $1.screenWidth * $1.screenHeight }?.monitor.id
            : nil
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [P.desk, P.deskLow], startPoint: .top, endPoint: .bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, frame.deskY)

            ForEach(desk.placements, id: \.monitor.id) { placement in
                let bezel = max(3, placement.bezel * s)
                let chin = max(5, placement.chin * s)
                let screen = CGSize(width: placement.screenWidth * s, height: placement.screenHeight * s)
                let outer = CGSize(width: screen.width + bezel * 2, height: screen.height + bezel + chin)
                let left = frame.originX + placement.x * s
                let top = frame.deskY - outer.height - 1.96 * s
                let centre = left + outer.width / 2
                let footHeight = max(4, placement.footHeight * s)
                let neckWidth = max(8, placement.neckWidth * s)
                let footWidth = placement.footWidth * s
                let hasFault = workspace?.zones.contains { $0.plateID == nil && model.monitorKey($0) == placement.monitor.id && model.fault(of: $0) != nil } ?? false

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
                        .frame(width: outer.width)
                        .help(placement.monitor.name)
                        .offset(x: left, y: frame.deskY + (narrow ? 4 : 8))
                }
                .zIndex(hasFault ? 2 : 0)
            }

            if let workspace, let reference = desk.placements.first {
                let virtuals = model.pinnedVirtualPlates(in: workspace)
                ForEach(Array(virtuals.enumerated()), id: \.element.id) { index, plate in
                    let target = desk.placement(for: model.monitorKeyFor(plate.monitor)) ?? reference
                    let bezel = max(3, target.bezel * s)
                    let screen = CGSize(width: target.screenWidth * s, height: target.screenHeight * s)
                    let outer = CGSize(width: screen.width + bezel * 2, height: screen.height + bezel + max(5, target.chin * s))
                    let priorWidth = virtuals.prefix(index).reduce(CGFloat(0)) { partial, prior in
                        let priorTarget = desk.placement(for: model.monitorKeyFor(prior.monitor)) ?? reference
                        return partial + CGFloat(priorTarget.outerWidth) * s + plateGap * s
                    }
                    let x = frame.originX + CGFloat(desk.width) * s + priorWidth + plateGap * s
                    let top = frame.deskY - outer.height - 1.96 * s
                    VirtualPlateStation(model: model, workspace: workspace, plate: plate, monitor: target.monitor,
                                        screen: screen, bezel: bezel, outer: outer, deskY: frame.deskY,
                                        footHeight: max(4, target.footHeight * s), neckWidth: max(8, target.neckWidth * s),
                                        footWidth: target.footWidth * s, labelOffset: narrow ? 4 : 8,
                                        centre: x + outer.width / 2, top: top)
                        .frame(width: outer.width, height: max(outer.height, frame.deskY - top + 76))
                        .offset(x: x, y: top)
                }

                let tail = reference
                let ghostBezel = max(3, tail.bezel * s)
                let ghostScreen = CGSize(width: tail.screenWidth * s, height: tail.screenHeight * s)
                let ghostOuter = CGSize(width: ghostScreen.width + ghostBezel * 2,
                                        height: ghostScreen.height + ghostBezel + max(5, tail.chin * s))
                let priorWidth = virtuals.reduce(CGFloat(0)) { partial, plate in
                    let target = desk.placement(for: model.monitorKeyFor(plate.monitor)) ?? reference
                    return partial + CGFloat(target.outerWidth) * s + plateGap * s
                }
                let x = frame.originX + CGFloat(desk.width) * s + priorWidth + plateGap * s
                let top = frame.deskY - ghostOuter.height - 1.96 * s
                VirtualAddGhost(model: model, desk: desk, screen: ghostScreen, bezel: ghostBezel,
                                outer: ghostOuter, top: top, deskY: frame.deskY,
                                footHeight: max(4, tail.footHeight * s), neckWidth: max(8, tail.neckWidth * s),
                                footWidth: tail.footWidth * s, labelOffset: narrow ? 4 : 8)
                    .frame(width: ghostOuter.width, height: max(ghostOuter.height, frame.deskY - top + 52))
                    .offset(x: x, y: top)
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
        let zones = workspace?.zones.filter {
            model.monitorKey($0) == monitor.id && $0.plateID == nil
        } ?? []
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
                            Text("Set up \(monitor.name)")
                                .font(T.font(T.type.small))
                                .foregroundStyle(P.ink3)
                                .multilineTextAlignment(.center)
                            LinkButton(title: "+") { model.useMonitor(monitor) }
                                .help("Set up \(monitor.name)")
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

private struct VirtualPlateStation: View {
    @Bindable var model: SettingsModel
    let workspace: Workspace
    let plate: VirtualPlate
    let monitor: DeskMonitor
    let screen: CGSize
    let bezel: CGFloat
    let outer: CGSize
    let deskY: CGFloat
    let footHeight: CGFloat
    let neckWidth: CGFloat
    let footWidth: CGFloat
    let labelOffset: CGFloat
    let centre: CGFloat
    let top: CGFloat
    @State private var editingName = false

    private var zones: [Zone] { workspace.zones.filter { $0.plateID == plate.id } }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [P.standLow, P.standHigh, P.standLow], startPoint: .leading, endPoint: .trailing)
                .frame(width: neckWidth, height: max(0, deskY - top - footHeight - outer.height))
                .offset(x: outer.width / 2 - neckWidth / 2, y: outer.height)
            RoundedRectangle(cornerRadius: 3).fill(P.stand).overlay(RoundedRectangle(cornerRadius: 3).stroke(P.standEdge, lineWidth: 1))
                .frame(width: footWidth, height: footHeight)
                .offset(x: (outer.width - footWidth) / 2, y: deskY - top - footHeight)
            RoundedRectangle(cornerRadius: T.radii.bezel).fill(P.bezel)
                .overlay(RoundedRectangle(cornerRadius: T.radii.bezel).strokeBorder(P.selection.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                .frame(width: outer.width, height: outer.height)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(P.screenUnused).frame(width: screen.width, height: screen.height)
                ForEach(zones) { zone in
                    ZoneView(model: model, zone: zone, number: model.number(of: zone, in: workspace), screen: screen, offline: false)
                }
                if zones.isEmpty {
                    Button { model.useVirtualMonitor(plate.id) } label: {
                        VStack(spacing: screen.width < 130 ? 4 : 8) {
                            Text(model.virtualPlateName(plate))
                                .font(T.font(screen.width < 130 ? T.type.caption : T.type.small, .semibold)).foregroundStyle(P.ink2)
                                .lineLimit(1)
                            Text(screen.width < 130 ? "Set up\nzones" : "Set up zones")
                                .font(T.font(screen.width < 130 ? T.type.body : T.type.select, .bold)).foregroundStyle(P.ink)
                                .multilineTextAlignment(.center)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, screen.width < 130 ? 6 : 12)
                                .padding(.vertical, screen.width < 130 ? 3 : 8)
                                .background(P.field, in: RoundedRectangle(cornerRadius: T.radii.field))
                                .overlay(RoundedRectangle(cornerRadius: T.radii.field).strokeBorder(P.fieldBorder, lineWidth: 1))
                        }
                        .padding(screen.width < 130 ? 4 : 8)
                        .frame(width: outer.width, height: outer.height)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).focusRing()
                    .offset(x: -bezel, y: -bezel)
                    .accessibilityLabel("Set up zones for \(model.virtualPlateName(plate))")
                    .help("Click anywhere on this plate to set up zones")
                }
            }
            .offset(x: bezel, y: bezel)
            Group {
                if editingName {
                    TextField("Virtual desktop", text: Binding(get: { model.virtualPlateName(plate) }, set: { model.renameVirtualPlate(plate.id, to: $0) }))
                        .textFieldStyle(.plain).multilineTextAlignment(.center).font(T.font(T.type.body, .bold))
                        .onSubmit { editingName = false }
                } else {
                    Text(model.virtualPlateName(plate)).font(T.font(T.type.body, .bold)).foregroundStyle(P.ink)
                        .onTapGesture(count: 2) { editingName = true }
                }
            }
            .lineLimit(1).frame(width: outer.width)
            .help(model.virtualPlateName(plate))
            .offset(y: deskY - top + labelOffset)
            VStack(spacing: 3) {
              HStack(spacing: 5) {
                Text(outer.width < 130 ? "macOS \(model.desktopOrdinal(plate.desktopID))" : model.desktopDescription(plate))
                    .font(T.font(T.type.label, .semibold)).foregroundStyle(P.ink2)
                    .lineLimit(1)
                    .accessibilityLabel(model.desktopDescription(plate))
                    .help(model.desktopDescription(plate))
                Button { model.benchVirtualPlate(plate.id) } label: { Icon(kind: .tray, size: 11) }
                    .buttonStyle(.plain).help("Move to Bench")
              }
              HStack(spacing: 6) {
                Button(outer.width < 140 ? "Show" : "Show desktop") { model.showDesktop(plate) }
                    .font(T.font(outer.width < 90 ? 10 : T.type.label, .semibold)).foregroundStyle(P.ink2)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .buttonStyle(.plain).focusRing()
                    .accessibilityLabel("Show \(model.desktopDescription(plate))")
                DesktopSetupsControl(model: model, plate: plate, compact: true)
              }
            }
            .frame(width: outer.width)
            .offset(y: deskY - top + labelOffset + 20)
        }
        .frame(width: outer.width, height: max(outer.height, deskY - top + 76), alignment: .topLeading)
    }
}

private struct VirtualAddGhost: View {
    @Bindable var model: SettingsModel
    let desk: DeskArrangement
    let screen: CGSize
    let bezel: CGFloat
    let outer: CGSize
    let top: CGFloat
    let deskY: CGFloat
    let footHeight: CGFloat
    let neckWidth: CGFloat
    let footWidth: CGFloat
    let labelOffset: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [P.standLow, P.standHigh, P.standLow], startPoint: .leading, endPoint: .trailing)
                .frame(width: neckWidth, height: max(0, deskY - top - footHeight - outer.height))
                .offset(x: outer.width / 2 - neckWidth / 2, y: outer.height)
            RoundedRectangle(cornerRadius: 3).fill(P.stand)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(P.standEdge, lineWidth: 1))
                .frame(width: footWidth, height: footHeight)
                .offset(x: (outer.width - footWidth) / 2, y: deskY - top - footHeight)
            Button {
                model.selectedVirtualMonitorID = nil
                model.selectedBenchedPlateID = nil
                model.showingVirtualChoices = true
            } label: {
                VStack(spacing: 5) {
                    Text("+").font(T.font(30, .regular)).foregroundStyle(P.ink2)
                    if screen.width >= 110 && screen.height >= 70 {
                        Text("Virtual desktop").font(T.font(T.type.small, .semibold)).foregroundStyle(P.ink2)
                    }
                }
                .frame(width: screen.width, height: screen.height)
                .background(P.screenUnused.opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: T.radii.chip).strokeBorder(P.ink3, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            }
            .buttonStyle(.plain)
            .disabled(!model.status.spaceSnapshot.available)
            .help(model.status.spaceSnapshot.available ? "Add a virtual desktop" : "Desktop detection is unavailable")
            .accessibilityLabel("Add a virtual desktop")
            .padding(bezel)
            .frame(width: outer.width, height: outer.height)
            .popover(isPresented: $model.showingVirtualChoices, arrowEdge: .bottom) {
                VirtualDesktopPicker(model: model, desk: desk).padding(12).frame(minWidth: 250)
            }
            Text("Add a desktop").font(T.font(T.type.label)).foregroundStyle(P.ink2)
                .lineLimit(1).frame(width: outer.width)
                .offset(y: deskY - top + labelOffset)
        }
        .frame(width: outer.width, height: max(outer.height, deskY - top + 52), alignment: .topLeading)
    }
}

private struct VirtualDesktopPicker: View {
    @Bindable var model: SettingsModel
    let desk: DeskArrangement
    private var monitors: [DeskMonitor] { desk.monitors.filter(\.isConnected) }

    var body: some View {
        let target = model.selectedBenchedPlateID.flatMap { id in model.selectedWorkspace?.virtualPlates.first { $0.id == id } }
        let monitorID = target.map { model.monitorKeyFor($0.monitor) } ?? model.selectedVirtualMonitorID
            ?? (monitors.count == 1 ? monitors.first?.id : nil)
        let uuid = target?.monitor.uuid ?? monitors.first { $0.id == monitorID }?.reference.uuid
        let spaces = model.status.spaceSnapshot.displays.filter { uuid == nil || $0.displayUUID == uuid }
            .flatMap { display in display.spaces.filter { !$0.isFullscreen } }
        VStack(alignment: .leading, spacing: 8) {
            if monitors.count > 1 && monitorID == nil {
                Text("Choose a monitor").font(T.font(T.type.small, .semibold))
                HStack {
                    ForEach(monitors) { monitor in
                        Button(monitor.name) { model.selectedVirtualMonitorID = monitor.id }
                            .buttonStyle(InkButtonStyle(kind: .secondary))
                    }
                }
            } else {
                Text(target == nil ? "Choose a desktop" : "Pin \(target!.name) to a desktop")
                    .font(T.font(T.type.small, .semibold))
                ForEach(spaces, id: \.uuid) { desktop in
                    let alreadyUsed = model.selectedWorkspace?.virtualPlates.contains {
                        $0.id != target?.id && $0.desktopID == desktop.uuid && model.monitorKeyFor($0.monitor) == monitorID
                    } ?? false
                    Button(desktop.label) {
                        guard let monitor = monitors.first(where: { $0.id == monitorID }) else { return }
                        if let target { model.pinVirtualPlate(target.id, to: desktop) }
                        else { model.addVirtualPlate(on: monitor, desktop: desktop) }
                        model.selectedBenchedPlateID = nil
                        model.selectedVirtualMonitorID = nil
                        model.showingVirtualChoices = false
                    }
                    .buttonStyle(InkButtonStyle(kind: .dashed, height: 26)).disabled(alreadyUsed)
                }
            }
            Button("Cancel") {
                model.showingVirtualChoices = false
                model.selectedVirtualMonitorID = nil
                model.selectedBenchedPlateID = nil
            }.buttonStyle(InkButtonStyle(kind: .quiet, height: 24))
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
        let note = faultText(fault) ?? program.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "Drop target"
        let chip = Text("\(number)")
            .font(T.font(width < 36 ? 11 : T.type.body, .extraBold).monospacedDigit())
            .lineLimit(1).minimumScaleFactor(0.5)
            .foregroundStyle(selected ? P.onSelection : P.ink)
            .padding(.horizontal, width < 36 ? 2 : 5)
            .frame(minWidth: min(22, max(0, width - (tiny ? 8 : 16))), minHeight: min(22, height))
            .background(RoundedRectangle(cornerRadius: T.radii.chip).fill(selected ? P.selection : P.zoneChip))
        let title = Text(name)
            .font(T.font(size, program == nil ? .semibold : .bold))
            .foregroundStyle(program == nil ? P.ink2 : P.ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: max(0, width - (inline ? 22 + 12 : tiny ? 8 : 16)), alignment: .leading)

        Button { model.selectZone(zone.id) } label: {
            Group {
                if width < 64 || height < 28 {
                    chip
                } else if inline {
                    HStack(spacing: 6) {
                        chip
                        title
                    }
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        chip
                        title
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
        .help(name)
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
        let physicalZones = workspace.zones.filter { $0.plateID == nil }
        let apps = physicalZones.filter { !($0.program ?? "").isEmpty }.count
        let zones = physicalZones.count == 1 ? "1 zone" : "\(physicalZones.count) zones"
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
