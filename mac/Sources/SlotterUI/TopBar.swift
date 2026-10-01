import SlotterKit
import SwiftUI

private let P = T.palette

/// Width classes from the design: tabs become a switcher below 1000, the drawer reflows below 760.
struct DesignerLayout {
    let width: CGFloat
    let height: CGFloat
    var wide: Bool { width >= 1000 }
    var narrow: Bool { width < 760 }
    /// The drawer takes its four short rows below 860, earlier than the rest of the narrow layout,
    /// so the desk keeps its height; from 860 to 1000 it stays three compact columns.
    var stacked: Bool { width < 860 }
}

/// Workspaces as tabs across the top, grouped by the monitors they use.
struct TopBar: View {
    @Bindable var model: SettingsModel
    let layout: DesignerLayout
    @FocusState private var renameFocused: Bool

    private var barHeight: CGFloat { layout.narrow ? 46 : 48 }

    var body: some View {
        let desk = model.desk
        HStack(spacing: layout.narrow ? 8 : 14) {
            if layout.wide {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        tabs(desk)
                        newWorkspaceButton.padding(.leading, 10)
                    }
                    compact(desk)
                }
            } else {
                compact(desk)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, layout.narrow ? 12 : 20)
        .padding(.trailing, layout.narrow ? 10 : 16)
        .frame(height: barHeight)
        .overlay(alignment: .bottom) { Rectangle().fill(P.rule).frame(height: 1) }
        .onChange(of: model.focusRequest) { _, request in
            guard request == .rename else { return }
            renameFocused = true
            model.focusRequest = nil
        }
    }

    @ViewBuilder
    private func compact(_ desk: DeskArrangement) -> some View {
        if model.renaming != nil {
            nameRow
        } else {
            switcher(desk)
        }
    }

    // MARK: Tabs

    private func tabs(_ desk: DeskArrangement) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(model.groups(in: desk).enumerated()), id: \.offset) { index, group in
                GroupLabel(keys: group.keys, desk: desk, model: model)
                    .padding(.leading, index == 0 ? 0 : 14)
                    .padding(.trailing, 6)
                ForEach(group.workspaces) { workspace in
                    if model.renaming?.workspaceID == workspace.id {
                        renameTab(workspace)
                    } else {
                        tab(workspace)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func tab(_ workspace: Workspace) -> some View {
        let on = workspace.id == model.selectedWorkspaceID
        return HStack(spacing: 0) {
            TabButton(title: workspace.name, on: on, offline: model.isFullyOffline(workspace)) {
                model.selectWorkspace(workspace.id)
            }
            if on {
                Menu {
                    Button("Rename workspace") { model.beginRename() }
                    Button("Remove workspace") { model.removeSelectedWorkspace() }
                    stopUsingItem()
                } label: {
                    Icon(kind: .dots, size: 14)
                        .foregroundStyle(P.ink2)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.trailing, 4)
                .accessibilityLabel("Options for \(workspace.name)")
            }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if on {
                Rectangle().fill(P.selection).frame(height: 3).padding(.horizontal, 8).offset(y: 1)
            }
        }
    }

    private func renameTab(_ workspace: Workspace) -> some View {
        renameField(width: 150)
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if let error = model.renameError {
                    (Text("Cannot rename \(workspace.name). ").font(T.font(T.type.small, .bold)).foregroundColor(P.error)
                        + Text(error).font(T.font(T.type.small)).foregroundColor(P.ink))
                        .lineSpacing(2)
                        .frame(width: 280, alignment: .leading)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: T.radii.field).fill(P.errorGround))
                        .overlay(RoundedRectangle(cornerRadius: T.radii.field).strokeBorder(P.error, lineWidth: 1))
                        .floatingShadow()
                        .offset(x: 6, y: barHeight + 6)
                        .accessibilityLabel(error)
                }
            }
    }

    private func renameField(width: CGFloat) -> some View {
        InkTextField(text: Binding(get: { model.renaming?.value ?? "" },
                                   set: { model.renaming?.value = $0 }),
                     font: T.font(T.type.tab, .semibold),
                     focus: $renameFocused)
            .padding(.horizontal, 8)
            .frame(width: width, height: 30)
            .box(invalid: model.renameError != nil)
            .onSubmit { model.commitRename() }
            .onExitCommand { model.cancelRename() }
            .accessibilityLabel("Workspace name")
    }

    private var newWorkspaceButton: some View {
        Button { model.addWorkspace() } label: {
            HStack(spacing: 6) {
                Icon(kind: .plus, size: 12)
                Text("New workspace")
            }
        }
        .buttonStyle(InkButtonStyle(kind: .dashed, height: 30))
    }

    // MARK: Compact

    private func switcher(_ desk: DeskArrangement) -> some View {
        let workspace = model.selectedWorkspace
        let caption = workspace.map { model.isFullyOffline($0) ? "offline" : names(model.monitorKeys(of: $0, in: desk), desk) } ?? ""
        return Menu {
            ForEach(Array(model.groups(in: desk).enumerated()), id: \.offset) { _, group in
                Section(names(group.keys, desk).isEmpty ? "No monitor" : names(group.keys, desk)) {
                    ForEach(group.workspaces) { item in
                        Button { model.selectWorkspace(item.id) } label: {
                            if item.id == model.selectedWorkspaceID {
                                Label(item.name, systemImage: "checkmark")
                            } else {
                                Text(model.isFullyOffline(item) ? "\(item.name) (offline)" : item.name)
                            }
                        }
                    }
                }
            }
            Divider()
            Button("New workspace") { model.addWorkspace() }
            if let workspace {
                Button("Rename \(workspace.name)") { model.beginRename() }
                Button("Remove \(workspace.name)") { model.removeSelectedWorkspace() }
                stopUsingItem()
            }
        } label: {
            HStack(spacing: 8) {
                Text(workspace?.name ?? "No workspaces")
                    .font(T.font(T.type.switcher, .bold))
                    .foregroundStyle(P.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !caption.isEmpty {
                    Text(caption).font(T.font(T.type.label)).foregroundStyle(P.ink3).lineLimit(1).fixedSize()
                }
                Icon(kind: .chevron, size: 10).foregroundStyle(P.ink2)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .frame(maxWidth: 260, alignment: .leading)
            .fixedSize()
            .box()
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var nameRow: some View {
        let workspace = model.workspaces.first { $0.id == model.renaming?.workspaceID }
        return HStack(spacing: 10) {
            Text("Rename \(workspace?.name ?? "")")
                .font(T.font(T.type.small))
                .foregroundStyle(P.ink2)
                .lineLimit(1)
                .fixedSize()
            renameField(width: 140)
            if let error = model.renameError {
                Text(error).font(T.font(T.type.small, .bold)).foregroundStyle(P.error).lineLimit(2)
            } else {
                Text("Press Return to keep it.").font(T.font(T.type.small)).foregroundStyle(P.ink).lineLimit(2)
            }
        }
    }

    /// A workspace stops using a monitor from here, the one home it has, as on Windows.
    @ViewBuilder
    private func stopUsingItem() -> some View {
        if model.canStopUsingSelectedMonitor(), let zone = model.selectedZone {
            let name = model.desk.monitors.first { $0.id == model.monitorKey(zone) }?.name ?? "this monitor"
            Divider()
            Button("Stop using \(name)") { model.stopUsingSelectedMonitor() }
        }
    }

    private func names(_ keys: [String], _ desk: DeskArrangement) -> String {
        keys.compactMap { key in desk.monitors.first { $0.id == key }?.name }.joined(separator: " + ")
    }
}

private struct TabButton: View {
    let title: String
    let on: Bool
    let offline: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                    .font(T.font(T.type.tab, .semibold))
                    .foregroundStyle(on || hovering ? P.ink : P.ink2)
                    .lineLimit(1)
                    .fixedSize()
                if offline { Tag("Offline") }
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .focusRing()
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A group heading: the monitor pair in miniature with the used ones filled, then their names.
private struct GroupLabel: View {
    let keys: [String]
    let desk: DeskArrangement
    let model: SettingsModel

    var body: some View {
        let used = Set(keys)
        let names = keys.compactMap { key in desk.monitors.first { $0.id == key }?.name }
        let allOff = !keys.isEmpty && keys.allSatisfy(model.isOffline)
        HStack(spacing: 6) {
            Canvas { context, size in
                let placements = desk.placements
                let height = placements.map { $0.y + $0.outerHeight }.max() ?? 1
                let k = min((size.width - 1) / desk.width, (size.height - 1) / height)
                for placement in placements {
                    let rect = CGRect(x: 0.5 + placement.x * k, y: 0.5 + placement.y * k,
                                      width: placement.outerWidth * k, height: placement.outerHeight * k)
                    let path = Path(roundedRect: rect, cornerRadius: 1)
                    if used.contains(placement.monitor.id) { context.fill(path, with: .foreground) }
                    context.stroke(path, with: .foreground, lineWidth: 1)
                }
            }
            .frame(width: 22, height: 12)
            Text((names.isEmpty ? "No monitor" : names.joined(separator: " + ")).uppercased() + (allOff ? " · DISCONNECTED" : ""))
                .font(T.font(T.type.label, .medium))
                .tracking(T.faces.labelTracking)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(P.ink3)
        .accessibilityElement(children: .combine)
    }
}
