import AppKit
import Carbon.HIToolbox
import Observation
import SlotterKit
import SwiftUI

private let P = T.palette

/// The inspector: a drawer under the desk with its faces on the top edge.
/// Clicking the open tab shuts it.
struct DrawerView: View {
    @Bindable var model: SettingsModel
    let layout: DesignerLayout

    var body: some View {
        let zone = model.selectedZone
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                HStack(alignment: .bottom, spacing: 4) {
                    DrawerTab(title: zoneTitle(zone), selected: model.face == .zone, enabled: zone != nil) {
                        model.toggleFace(.zone)
                    }
                    DrawerTab(title: "Slotter settings", selected: model.face == .settings, enabled: true) {
                        model.toggleFace(.settings)
                    }
                    DrawerTab(title: "Shortcuts", selected: model.face == .shortcuts, enabled: true) {
                        model.toggleFace(.shortcuts)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 46, alignment: .bottom)
            .padding(.leading, layout.narrow ? 12 : 24)
            .padding(.trailing, layout.narrow ? 12 : 16)
            .zIndex(1)

            if model.face == .zone, let zone, let workspace = model.selectedWorkspace {
                ZoneFace(model: model, zone: zone, workspace: workspace, layout: layout)
                    .modifier(Face(narrow: layout.stacked))
            } else if model.face == .settings {
                VStack(alignment: .leading, spacing: 12) {
                    if let plate = model.selectedWorkspace?.virtualPlates.first(where: { $0.id == model.selectedVirtualPlateID }) {
                        VirtualPlateNameField(model: model, plate: plate)
                    }
                    SettingsFace(model: model, layout: layout)
                }
                    .modifier(Face(narrow: layout.stacked))
            } else if model.face == .shortcuts {
                ScrollView(.vertical) {
                    ShortcutsFace(model: model, layout: layout)
                        .modifier(Face(narrow: layout.stacked))
                }
                .frame(height: min(360, max(160, layout.height - 360)))
            }
        }
        .background(P.drawer)
        .overlay(alignment: .top) { Rectangle().fill(P.rule).frame(height: 1) }
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3)
                .fill(P.drawerPull)
                .frame(width: 56, height: 4)
                .offset(y: -1)
        }
    }

    private func zoneTitle(_ zone: Zone?) -> String {
        guard let zone, let workspace = model.selectedWorkspace else { return "Zone: none yet" }
        let name = model.desk.monitors.first { $0.id == model.monitorKey(zone) }?.name ?? "a monitor"
        return "Zone \(model.number(of: zone, in: workspace)) on \(name)"
    }
}

private struct Face: ViewModifier {
    let narrow: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, narrow ? 14 : 32)
            .padding(.top, narrow ? 10 : 14)
            .padding(.bottom, narrow ? 12 : 18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(P.drawerFace)
            .overlay(alignment: .top) { Rectangle().fill(P.rule).frame(height: 1) }
    }
}

private struct DrawerTab: View {
    let title: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: T.radii.tab, topTrailingRadius: T.radii.tab)
        // Not `.disabled`: that would dim "Zone: none yet" below ink-2.
        Button { if enabled { action() } } label: {
            Text(title)
                .font(T.font(T.type.small, .semibold))
                .foregroundStyle(selected ? P.ink : P.ink2)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background {
                    if selected {
                        shape.fill(P.drawerFace)
                            .overlay(shape.strokeBorder(P.rule, lineWidth: 1))
                            .overlay(alignment: .bottom) { Rectangle().fill(P.drawerFace).frame(height: 2).padding(.horizontal, 1) }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(y: 1)
        .focusRing(radius: T.radii.tab)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Zone face

private struct ZoneFace: View {
    @Bindable var model: SettingsModel
    let zone: Zone
    let workspace: Workspace
    let layout: DesignerLayout

    var body: some View {
        let key = model.monitorKey(zone)
        let monitor = model.desk.monitors.first { $0.id == key }
        let number = model.number(of: zone, in: workspace)
        let inner = layout.width - (layout.stacked ? 28 : 64)
        let virtualPlate = workspace.virtualPlates.first { $0.id == zone.plateID }

        VStack(alignment: .leading, spacing: 8) {
            if let virtualPlate { VirtualPlateNameField(model: model, plate: virtualPlate) }
            if layout.stacked {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    heading(number: number, monitor: monitor, compact: true)
                    Spacer(minLength: 0)
                    zoneIcons
                }
                HStack(spacing: 10) {
                    AppPicker(model: model, zone: zone, height: 34, size: T.type.switcher)
                    LinkButton(title: "Manage programs…") { model.showingPrograms = true }
                }
                PositionFields(model: model, zone: zone, number: number, monitor: monitor, compact: true)
                WrapLayout(spacing: 8, lineSpacing: 6) {
                    presets(key: key, compact: true)
                    Text(nowText(key)).font(T.font(T.type.small)).foregroundStyle(P.ink2).fixedSize().frame(height: 24)
                    LinkButton(title: "Reset monitor") { model.resetSelectedMonitor() }.frame(height: 24)
                }
            }
            } else if layout.wide {
            let unit = inner / 3.45
            HStack(alignment: .top, spacing: 0) {
                identity(number: number, monitor: monitor)
                    .frame(width: max(230, unit * 1.25) - 24, alignment: .topLeading)
                    .padding(.trailing, 24)
                Rectangle().fill(P.rule).frame(width: 1)
                PositionFields(model: model, zone: zone, number: number, monitor: monitor, compact: false)
                    .frame(width: max(250, unit) - 48, alignment: .topLeading)
                    .padding(.horizontal, 24)
                Rectangle().fill(P.rule).frame(width: 1)
                shape(key: key, monitor: monitor)
                    .padding(.leading, 24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)
            } else {
            // 860 to 1000: still three columns, so the drawer stays short and the desk leads.
            // The path drops out and the zone actions become icon buttons, as at 640.
            let rest = inner - 220 - 96
            let first = max(220, rest * 0.45)
            HStack(alignment: .top, spacing: 0) {
                identity(number: number, monitor: monitor, showsPath: false)
                    .frame(width: first, alignment: .topLeading)
                    .padding(.trailing, 24)
                Rectangle().fill(P.rule).frame(width: 1)
                PositionFields(model: model, zone: zone, number: number, monitor: monitor, compact: false, tightLabels: true)
                    .frame(width: 220, alignment: .topLeading)
                    .padding(.horizontal, 24)
                Rectangle().fill(P.rule).frame(width: 1)
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow("This zone").padding(.bottom, 6)
                    zoneIcons.padding(.bottom, 10)
                    Eyebrow("\(monitor?.name ?? "Monitor") layout").padding(.bottom, 6)
                    presets(key: key, compact: false).padding(.bottom, 6)
                    WrapLayout(spacing: 10, lineSpacing: 4) {
                        Text(nowText(key)).font(T.font(T.type.small)).foregroundStyle(P.ink2).fixedSize()
                        LinkButton(title: "Reset monitor") { model.resetSelectedMonitor() }
                    }
                }
                .padding(.leading, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var zoneIcons: some View {
        HStack(spacing: 4) {
            Button { model.splitSelectedZone(vertical: true) } label: { Icon(kind: .splitV) }
                .buttonStyle(IconButtonStyle()).help("Split vertically").accessibilityLabel("Split vertically")
                .disabled(!zone.isSplittableHorizontally)
            Button { model.splitSelectedZone(vertical: false) } label: { Icon(kind: .splitH) }
                .buttonStyle(IconButtonStyle()).help("Split horizontally").accessibilityLabel("Split horizontally")
                .disabled(!zone.isSplittableVertically)
            Button { model.deleteSelectedZone() } label: { Icon(kind: .delete) }
                .buttonStyle(IconButtonStyle(danger: true))
                .disabled(!model.canDeleteSelectedZone())
                .help(model.canDeleteSelectedZone() ? "Delete zone" : "A monitor keeps at least one zone. Use Reset monitor.")
                .accessibilityLabel("Delete zone")
        }
    }

    private func heading(number: Int, monitor: DeskMonitor?, compact: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(T.font(compact ? T.type.body : T.type.select, .extraBold).monospacedDigit())
                .foregroundStyle(P.onSelection)
                .padding(.horizontal, compact ? 5 : 7)
                .frame(minWidth: compact ? 22 : 28, minHeight: compact ? 22 : 28)
                .background(RoundedRectangle(cornerRadius: T.radii.field).fill(P.selection))
            Text("Zone \(number)")
                .font(T.font(compact ? T.type.select : T.type.heading, .extraBold))
                .tracking(-0.2)
                .foregroundStyle(P.ink)
            Text("on \(monitor?.name ?? "a monitor")\(monitor?.isConnected == false ? ", disconnected" : "")")
                .font(T.font(T.type.body, .medium))
                .foregroundStyle(P.ink2)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The path and arguments drop out below 1000 wide, as at 640; the Programs sheet shows them.
    private func identity(number: Int, monitor: DeskMonitor?, showsPath: Bool = true) -> some View {
        let program = model.program(named: zone.program)
        return VStack(alignment: .leading, spacing: 0) {
            heading(number: number, monitor: monitor, compact: false).padding(.bottom, 10)
            Eyebrow("Launches").padding(.bottom, 6)
            AppPicker(model: model, zone: zone, height: 40, size: T.type.select)
            if showsPath { Group {
                if let program {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(program.path.isEmpty ? "No application chosen yet." : program.path).foregroundStyle(P.ink2)
                        if !program.arguments.isEmpty {
                            Text("Arguments: \(program.arguments)").foregroundStyle(P.ink3)
                        }
                    }
                } else {
                    Text("Stays empty. Still a drop target: drag any window here and it snaps to this zone.")
                        .foregroundStyle(P.ink2)
                }
            }
            .font(T.font(T.type.small))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 7)
            .padding(.bottom, 6) } else { Color.clear.frame(height: 8) }
            LinkButton(title: "Manage programs…") { model.showingPrograms = true }
        }
    }

    private func shape(key: String, monitor: DeskMonitor?) -> some View {
        let canDelete = model.canDeleteSelectedZone()
        return VStack(alignment: .leading, spacing: 0) {
            Eyebrow("This zone").padding(.bottom, 6)
            WrapLayout(spacing: 6, lineSpacing: 6) {
                Button { model.splitSelectedZone(vertical: true) } label: {
                    HStack(spacing: 6) { Icon(kind: .splitV); Text("Split vertically") }
                }
                .buttonStyle(InkButtonStyle())
                .disabled(!zone.isSplittableHorizontally)
                Button { model.splitSelectedZone(vertical: false) } label: {
                    HStack(spacing: 6) { Icon(kind: .splitH); Text("Split horizontally") }
                }
                .buttonStyle(InkButtonStyle())
                .disabled(!zone.isSplittableVertically)
                Button { model.deleteSelectedZone() } label: {
                    HStack(spacing: 6) { Icon(kind: .delete); Text("Delete zone") }
                }
                .buttonStyle(InkButtonStyle(kind: .quietDanger))
                .disabled(!canDelete)
                .help(canDelete ? "" : "A monitor keeps at least one zone. Use Reset monitor.")
            }
            Color.clear.frame(height: 10)
            Eyebrow("\(monitor?.name ?? "Monitor") layout").padding(.bottom, 6)
            presets(key: key, compact: false).padding(.bottom, 6)
            WrapLayout(spacing: 10, lineSpacing: 4) {
                Text(nowText(key)).font(T.font(T.type.small)).foregroundStyle(P.ink2).fixedSize()
                LinkButton(title: "Reset monitor") { model.resetSelectedMonitor() }
            }
        }
    }

    private func presets(key: String, compact: Bool) -> some View {
        let current = model.presetMatch(on: key, in: workspace)
        let presets = SettingsModel.designerPresets
        let groups = [presets.prefix(4), presets[4..<6], presets[6..<7], presets.suffix(from: 7)]
        return VStack(alignment: .leading, spacing: 8) {
          WrapLayout(spacing: 10, lineSpacing: 4) {
            ForEach(groups.indices, id: \.self) { index in
                HStack(spacing: 4) {
                    ForEach(groups[index]) { preset in
                        PresetButton(preset: preset, pressed: current?.name == preset.name, compact: compact) {
                            model.applyPreset(preset)
                        }
                    }
                }
            }
          }
          WrapLayout(spacing: 8, lineSpacing: 6) {
              GridTool(model: model)
              Button("Fill free space") { model.fillFreeSpace() }
                  .buttonStyle(InkButtonStyle())
                  .disabled(model.freeSpace == nil)
                  .help("Add a slot in the largest empty rectangle. Existing slots stay in place.")
              Button("Undo") { model.undoLayout() }
                  .buttonStyle(InkButtonStyle(kind: .quiet))
                  .disabled(!model.canUndoLayout)
              Button("Redo") { model.redoLayout() }
                  .buttonStyle(InkButtonStyle(kind: .quiet))
                  .disabled(!model.canRedoLayout)
          }
        }
    }

    private func nowText(_ key: String) -> String {
        "Now: " + (model.presetMatch(on: key, in: workspace)?.name ?? "custom")
    }
}

private struct VirtualPlateNameField: View {
    @Bindable var model: SettingsModel
    let plate: VirtualPlate
    @FocusState private var focused: Bool
    @State private var draftName: String

    init(model: SettingsModel, plate: VirtualPlate) {
        self.model = model
        self.plate = plate
        _draftName = State(initialValue: model.virtualPlateName(plate))
    }

    var body: some View {
        WrapLayout(spacing: 8, lineSpacing: 6) {
            Text("Virtual plate").font(T.font(T.type.small, .semibold)).foregroundStyle(P.ink2)
            InkTextField(text: $draftName, font: T.font(T.type.body, .semibold), focus: $focused)
                .frame(width: 220, height: 30)
                .box(invalid: draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Virtual plate name")
                .onChange(of: draftName) { _, value in if focused { model.renameVirtualPlate(plate.id, to: value) } }
                .onChange(of: model.virtualPlateName(plate)) { _, value in if !focused { draftName = value } }
                .onSubmit { focused = false }
            Text(model.desktopDescription(plate))
                .font(T.font(T.type.small, .semibold)).foregroundStyle(P.ink2)
            if plate.desktopID != nil {
                Button("Show desktop") { model.showDesktop(plate) }.buttonStyle(InkButtonStyle(kind: .quiet))
            }
            DesktopSetupsControl(model: model, plate: plate)
            if model.selectedZone == nil {
                Button("Undo") { model.undoLayout() }.buttonStyle(InkButtonStyle(kind: .quiet)).disabled(!model.canUndoLayout)
                Button("Redo") { model.redoLayout() }.buttonStyle(InkButtonStyle(kind: .quiet)).disabled(!model.canRedoLayout)
            }
            if draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Enter a name.").font(T.font(T.type.small, .semibold)).foregroundStyle(P.error)
            }
        }
        .onChange(of: model.focusVirtualPlateName) { _, request in
            guard request else { return }
            focused = true
            model.focusVirtualPlateName = false
        }
    }
}

struct DesktopSetupsControl: View {
    @Bindable var model: SettingsModel
    let plate: VirtualPlate
    var compact = false
    @State private var showing = false
    @State private var name = ""
    @State private var error: String?
    @State private var saved = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            if compact {
                Button("Modes") { showing.toggle() }
                    .font(T.font(10, .semibold)).foregroundStyle(P.ink2)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .buttonStyle(.plain).focusRing()
            } else {
                Button("Setups…") { showing.toggle() }.buttonStyle(InkButtonStyle(kind: .quiet))
            }
        }
            .accessibilityLabel("Saved setups for \(model.virtualPlateName(plate))")
            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Desktop setups").font(T.font(T.type.heading, .bold))
                    Text("Load a mode onto this plate. Undo restores its previous zones.")
                        .font(T.font(T.type.small)).foregroundStyle(P.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.desktopSetups) { setup in
                                HStack {
                                    Text(setup.name).font(T.font(T.type.body, .semibold)).lineLimit(2)
                                    Spacer()
                                    Button("Load") { model.loadDesktopSetup(setup, onto: plate.id); showing = false }
                                        .buttonStyle(InkButtonStyle())
                                        .accessibilityLabel("Load setup \(setup.name)")
                                }
                            }
                            if model.desktopSetups.isEmpty {
                                Text("No saved setups yet.").font(T.font(T.type.small)).foregroundStyle(P.ink2)
                            }
                        }
                    }.frame(maxHeight: 180)
                    Divider().overlay(P.rule)
                    InkTextField(text: $name, font: T.font(T.type.body), focus: $nameFocused)
                        .frame(height: 30).box()
                        .accessibilityLabel("Setup name")
                        .onChange(of: name) { _, _ in error = nil; saved = false }
                    HStack {
                        Button("Save this layout") {
                            error = model.saveDesktopSetup(plate.id, name: name)
                            saved = error == nil
                        }.buttonStyle(InkButtonStyle())
                        Spacer()
                        Button("Done") { showing = false }.buttonStyle(InkButtonStyle(kind: .quiet))
                    }
                    if let error { Text(error).font(T.font(T.type.small)).foregroundStyle(P.error).fixedSize(horizontal: false, vertical: true) }
                    if saved { Text("Setup saved.").font(T.font(T.type.small)).foregroundStyle(P.ink2) }
                }
                .padding(16).frame(width: 340).background(P.floating)
            }
    }
}

private struct GridTool: View {
    @Bindable var model: SettingsModel
    @State private var showing = false
    @State private var columns = "5"
    @State private var rows = "2"

    private var grid: LayoutPreset? {
        guard let columns = Int(columns), let rows = Int(rows) else { return nil }
        return PresetCatalog.grid(columns: columns, rows: rows)
    }

    var body: some View {
        Button("Custom grid…") { showing.toggle() }
            .buttonStyle(InkButtonStyle())
            .help("Create evenly sized columns and rows on this monitor.")
            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom grid").font(T.font(T.type.heading, .bold))
                    countField("Columns", text: $columns)
                    countField("Rows", text: $rows)
                    Text(grid.map { "\($0.zones.count) equal slots. Replaces this monitor’s layout; assigned programs carry across in order." }
                         ?? "Enter whole numbers from 1 to 20.")
                        .font(T.font(T.type.small)).foregroundStyle(P.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Cancel") { showing = false }.buttonStyle(InkButtonStyle(kind: .quiet))
                        Spacer()
                        Button("Create grid") {
                            guard let grid else { return }
                            model.applyPreset(grid)
                            showing = false
                        }.buttonStyle(InkButtonStyle(kind: .primary)).disabled(grid == nil)
                    }
                }
                .font(T.font(T.type.body))
                .foregroundStyle(P.ink)
                .padding(16)
                .frame(width: 280)
                .background(P.drawerFace)
            }
    }

    private func countField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
            Spacer()
            TextField(label, text: text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .padding(8)
                .frame(width: 56)
                .box()
                .accessibilityLabel("\(label), 1 to 20")
            Stepper(label, value: Binding(get: { Int(text.wrappedValue) ?? 1 }, set: { text.wrappedValue = "\($0)" }), in: 1...20)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Adjust \(label.lowercased())")
        }
    }
}

private struct PresetButton: View {
    let preset: LayoutPreset
    let pressed: Bool
    let compact: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            PresetGlyph(zones: preset.zones.map { ($0.x, $0.y, $0.w, $0.h) })
                .foregroundStyle(pressed || hovering ? P.ink : P.ink2)
                .frame(width: compact ? 30 : 34, height: compact ? 24 : 26)
                .background(RoundedRectangle(cornerRadius: T.radii.chip).fill(P.field))
                .overlay(RoundedRectangle(cornerRadius: T.radii.chip)
                    .strokeBorder(pressed ? P.ink : hovering ? P.ink3 : P.fieldBorder, lineWidth: pressed ? 2 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(preset.name)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(pressed ? .isSelected : [])
        .focusRing(radius: T.radii.chip)
    }
}

/// The large control: which program this zone launches.
private struct AppPicker: View {
    @Bindable var model: SettingsModel
    let zone: Zone
    let height: CGFloat
    let size: CGFloat

    var body: some View {
        let current = model.program(named: zone.program)
        Menu {
            Button { model.assignProgram(nil) } label: {
                if current == nil { Label("None, leave it empty", systemImage: "checkmark") } else { Text("None, leave it empty") }
            }
            Divider()
            ForEach(model.programs) { program in
                Button { model.assignProgram(program.name) } label: {
                    if current?.id == program.id { Label(program.name, systemImage: "checkmark") } else { Text(program.name) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(current?.name ?? "None, leave it empty")
                    .font(T.font(size, .bold))
                    .foregroundStyle(P.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Icon(kind: .chevron, size: 12).foregroundStyle(P.ink2)
            }
            .padding(.horizontal, 12)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .box(radius: T.radii.select)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .focusRing(radius: T.radii.select)
        .accessibilityLabel("Launches")
    }
}

private struct PositionFields: View {
    @Bindable var model: SettingsModel
    let zone: Zone
    let number: Int
    let monitor: DeskMonitor?
    let compact: Bool
    var tightLabels = false

    var body: some View {
        let fault = model.fault(of: zone)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if !compact { Eyebrow("Position and size") }
                Spacer(minLength: 0)
                Picker("Measurements", selection: $model.measurementUnit) {
                    Text("Percent").tag(SettingsModel.MeasurementUnit.percent)
                    Text("Pixels").tag(SettingsModel.MeasurementUnit.pixels)
                        .disabled(!model.canMeasurePixels)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .help("Measurements use the monitor’s work area, excluding the menu bar and Dock. Pixels require a connected monitor.")
            }.padding(.bottom, 6)
            if compact {
                HStack(spacing: 6) {
                    ForEach(SettingsModel.Field.allCases, id: \.self) { field in
                        PercentField(model: model, zone: zone, field: field, bad: isBad(field, fault), compact: true)
                    }
                }
            } else {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        PercentField(model: model, zone: zone, field: .x, bad: false, compact: tightLabels)
                        PercentField(model: model, zone: zone, field: .y, bad: false, compact: tightLabels)
                    }
                    GridRow {
                        PercentField(model: model, zone: zone, field: .w, bad: isBad(.w, fault), compact: tightLabels)
                        PercentField(model: model, zone: zone, field: .h, bad: isBad(.h, fault), compact: tightLabels)
                    }
                }
            }
            if let fault { message(fault).padding(.top, 8) }
        }
    }

    private func isBad(_ field: SettingsModel.Field, _ fault: SettingsModel.ZoneFault?) -> Bool {
        switch fault {
        case .pastRight: field == .w
        case .pastBottom: field == .h
        default: false
        }
    }

    private func message(_ fault: SettingsModel.ZoneFault) -> some View {
        let name = monitor?.name ?? "the monitor"
        let lead: String
        var detail = ""
        var fits = false
        switch fault {
        case .empty: lead = "Width and Height must each be at least 1% of the work area."
        case .negative: lead = "Left and Top cannot be below 0%."
        case .pastRight:
            lead = "Width takes zone \(number) past the right edge of \(name)."
            detail = " From Left \(Percent.text(zone.x))%, the most it can be is \(Percent.text(100 - zone.x))%."
            fits = true
        case .pastBottom:
            lead = "Height takes zone \(number) past the bottom edge of \(name)."
            detail = " From Top \(Percent.text(zone.y))%, the most it can be is \(Percent.text(100 - zone.y))%."
            fits = true
        }
        return HStack(alignment: .top, spacing: 8) {
            Icon(kind: .warn, size: 14).foregroundStyle(P.error).padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                (Text(lead).font(T.font(T.type.small, .bold)).foregroundColor(P.error)
                    + Text(detail).font(T.font(T.type.small)).foregroundColor(P.ink))
                    .fixedSize(horizontal: false, vertical: true)
                if fits { LinkButton(title: "Fit to the edge") { model.fitSelectedZone() } }
            }
        }
    }
}

private struct PercentField: View {
    @Bindable var model: SettingsModel
    let zone: Zone
    let field: SettingsModel.Field
    let bad: Bool
    let compact: Bool
    @State private var text: String
    @FocusState private var focused: Bool

    init(model: SettingsModel, zone: Zone, field: SettingsModel.Field, bad: Bool, compact: Bool) {
        self.model = model
        self.zone = zone
        self.field = field
        self.bad = bad
        self.compact = compact
        let raw: Double = switch field { case .x: zone.x; case .y: zone.y; case .w: zone.w; case .h: zone.h }
        _text = State(initialValue: model.unitSymbol == "px" ? String(format: "%.0f", model.displayValue(field, for: zone)) : Percent.text(raw))
    }

    private var value: Double {
        model.displayValue(field, for: zone)
    }

    private var formattedValue: String {
        model.unitSymbol == "px" ? String(format: "%.0f", value) : String(format: "%.2f", value)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    private var label: String {
        switch field {
        case .x: "Left"
        case .y: "Top"
        case .w: "Width"
        case .h: "Height"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(T.font(T.type.small))
                .foregroundStyle(P.ink2)
                .lineLimit(1)
                .fixedSize()
                .frame(width: compact ? nil : 52, alignment: .leading)
                .padding(.leading, compact ? 8 : 10)
                .padding(.trailing, compact ? 4 : 0)
            InkTextField(text: $text, font: T.font(T.type.tab, .semibold).monospacedDigit(),
                         alignment: .trailing, focus: $focused)
                .padding(.horizontal, 2)
            Text(model.unitSymbol)
                .font(T.font(T.type.body))
                .foregroundStyle(P.ink2)
                .padding(.leading, compact ? 1 : 2)
                .padding(.trailing, compact ? 7 : 10)
        }
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .box(invalid: bad)
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: T.radii.field + 1).strokeBorder(P.ink, lineWidth: 2).padding(-3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onChange(of: value) { _, _ in if !focused { text = formattedValue } }
        .onChange(of: zone.id) { _, _ in model.endGeometryEdit(); text = formattedValue }
        .onChange(of: model.unitSymbol) { _, _ in model.endGeometryEdit(); text = formattedValue }
        .onChange(of: text) { _, newValue in
            // The field shows one decimal of a value stored to two; only a real edit may write
            // back, or merely showing 33.3 would overwrite 33.33.
            guard focused, newValue != formattedValue,
                  let parsed = Double(newValue.replacingOccurrences(of: ",", with: ".")) else { return }
            if abs(parsed - value) > 0.001 { model.setDisplayValue(field, parsed) }
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused { model.beginGeometryEdit(); text = formattedValue }
            else { model.endGeometryEdit(); text = formattedValue }
        }
        .onChange(of: model.focusRequest) { _, request in
            guard request == .field(field) else { return }
            focused = true
            model.focusRequest = nil
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(model.unitSymbol == "px" ? "pixels" : "percent")")
    }
}

// MARK: - Settings face

private struct SettingsFace: View {
    @Bindable var model: SettingsModel
    let layout: DesignerLayout

    var body: some View {
        if layout.stacked {
            VStack(alignment: .leading, spacing: 6) {
                Text("Slotter settings").font(T.font(T.type.select, .extraBold)).foregroundStyle(P.ink).padding(.bottom, 0)
                login
                accessibility
                updates
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Slotter settings").font(T.font(T.type.heading, .extraBold)).tracking(-0.2).foregroundStyle(P.ink)
                    login
                    updates
                }
                .padding(.trailing, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                Rectangle().fill(P.rule).frame(width: 1)
                accessibility
                    .padding(.leading, 24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var login: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Start at login").font(T.font(T.type.body, .bold)).foregroundStyle(P.ink)
                if model.status.loginNeedsApproval {
                    Text("macOS is waiting for your approval in Login Items.")
                        .font(T.font(T.type.small)).foregroundStyle(P.error)
                    LinkButton(title: "Open Login Items") { model.actions.openLoginItemsSettings() }
                } else {
                    Text("Sits in the menu bar from login.").font(T.font(T.type.small)).foregroundStyle(P.ink2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            SwitchPill(isOn: model.startAtLogin) {
                model.toggleStartAtLogin()
            }
            .accessibilityLabel("Start at login")
        }
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility permission").font(T.font(T.type.body, .bold)).foregroundStyle(P.ink)
                if model.status.accessibilityTrusted {
                    StateLine(ok: true, text: "Granted. Slotter can move windows.")
                } else {
                    StateLine(ok: false, text: "Not granted. Slotter cannot move other apps’ windows until it is.")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            WrapLayout(spacing: 6, lineSpacing: 6) {
                if !model.status.accessibilityTrusted {
                    Button("Open System Settings") { model.actions.openAccessibilitySettings() }
                        .buttonStyle(InkButtonStyle())
                }
            }
        }
    }

    private var updates: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Updates").font(T.font(T.type.body, .bold)).foregroundStyle(P.ink)
                    Text("Check automatically once a day.")
                        .font(T.font(T.type.small)).foregroundStyle(P.ink2)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                SwitchPill(isOn: model.status.automaticUpdates) {
                    model.actions.setAutomaticUpdates(!model.status.automaticUpdates)
                }
                .accessibilityLabel("Check for updates automatically")
            }
            Button("Check now") { model.actions.checkForUpdates() }
                .buttonStyle(InkButtonStyle())
                .disabled(!model.status.canCheckForUpdates)
        }
        .padding(.top, 8)
    }
}

private struct StateLine: View {
    let ok: Bool
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Icon(kind: ok ? .check : .warn, size: 12).padding(.top, 1)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(T.font(T.type.small, .semibold))
        .foregroundStyle(ok ? P.ink : P.error)
    }
}

private struct Kbd: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }

    var body: some View {
        Text(keys)
            .font(T.font(T.type.small, .bold))
            .foregroundStyle(P.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: T.radii.chip).fill(P.field))
            .overlay(RoundedRectangle(cornerRadius: T.radii.chip).strokeBorder(P.fieldBorder, lineWidth: 1))
            .overlay(alignment: .bottom) { Rectangle().fill(P.fieldBorder).frame(height: 1).padding(.horizontal, 2) }
            .fixedSize()
    }
}

private struct ShortcutsFace: View {
    @Bindable var model: SettingsModel
    let layout: DesignerLayout
    @State private var recorder = ShortcutRecorder()

    private let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "Halves", actions: [.leftHalf, .rightHalf, .topHalf, .bottomHalf]),
        ShortcutGroup(title: "Corners", actions: [.topLeft, .topRight, .bottomLeft, .bottomRight]),
        ShortcutGroup(title: "Thirds", actions: [.leftThird, .centreThird, .rightThird, .leftTwoThirds, .rightTwoThirds]),
        ShortcutGroup(title: "Other", actions: [.maximise, .centre, .restore]),
        ShortcutGroup(title: "Displays", actions: [.nextDisplay, .previousDisplay]),
    ]

    private var columns: [ShortcutColumn] {
        [ShortcutColumn(id: "layout", groups: Array(groups[0...1])),
         ShortcutColumn(id: "sizes", groups: Array(groups[2...3])),
         ShortcutColumn(id: "displays", groups: [groups[4]])]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Snap shortcuts").font(T.font(T.type.heading, .extraBold)).foregroundStyle(P.ink)
                Spacer(minLength: 12)
                if MagnetLayouts.table(overrides: model.shortcuts) != MagnetLayouts.defaults {
                    LinkButton(title: "Reset all") { model.resetShortcuts() }
                }
            }
            HStack(alignment: .top, spacing: layout.stacked ? 10 : 30) {
                ForEach(columns) { column in
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(column.groups) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.title).font(T.font(T.type.body, .bold)).foregroundStyle(P.ink2)
                                ForEach(group.actions, id: \.self) { action in
                                    ShortcutRow(model: model, action: action, recorder: recorder)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .onDisappear { recorder.cancel() }
    }
}

private struct ShortcutGroup: Identifiable {
    let title: String
    let actions: [SnapAction]
    var id: String { title }
}

private struct ShortcutColumn: Identifiable {
    let id: String
    let groups: [ShortcutGroup]
}

private struct ShortcutRow: View {
    @Bindable var model: SettingsModel
    let action: SnapAction
    let recorder: ShortcutRecorder

    private var combo: KeyCombo? { MagnetLayouts.table(overrides: model.shortcuts)[action] }
    private var differsFromDefault: Bool { combo != MagnetLayouts.defaults[action] }
    private var unavailable: Bool { model.status.unavailableShortcuts.contains(action.rawValue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(action.title)
                    .font(T.font(T.type.small, .semibold))
                    .foregroundStyle(P.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    recorder.begin(action) { target, value in
                        if let value,
                           let conflict = ShortcutRules.conflict(for: value, excluding: target,
                                                                 overrides: model.shortcuts) {
                            recorder.showConflict("Already used by \(conflict.title). Rebind that action first.")
                        } else {
                            model.setShortcut(target, combo: value)
                        }
                    }
                } label: {
                    Kbd(recorder.recording == action ? "Press keys…" : (combo?.display ?? "Unbound"))
                }
                .buttonStyle(.plain)
                .help("Record a shortcut for \(action.title)")
                .accessibilityLabel("\(action.title), \(combo?.display ?? "unbound"). Record shortcut")
                if differsFromDefault {
                    LinkButton(title: "Reset", size: T.type.caption) { model.resetShortcut(action) }
                }
            }
            if recorder.action == action, let error = recorder.error {
                StateLine(ok: false, text: error)
            } else if unavailable {
                StateLine(ok: false, text: "Unavailable: another app holds this shortcut.")
            }
        }
    }
}

@MainActor
@Observable
private final class ShortcutRecorder {
    private(set) var recording: SnapAction?
    private(set) var action: SnapAction?
    private(set) var error: String?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var onCapture: ((SnapAction, KeyCombo?) -> Void)?

    func begin(_ action: SnapAction, onCapture: @escaping (SnapAction, KeyCombo?) -> Void) {
        cancel()
        self.action = action
        recording = action
        error = nil
        self.onCapture = onCapture
        ShortcutCenter.shared.suspendForRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let modifierFlags = event.modifierFlags.rawValue
            let consumed = MainActor.assumeIsolated {
                self?.consume(keyCode: keyCode, modifierFlags: modifierFlags) ?? false
            }
            return consumed ? nil : event
        }
    }

    func showConflict(_ message: String) { error = message }

    func cancel() {
        guard recording != nil else { action = nil; error = nil; return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        action = nil
        error = nil
        onCapture = nil
        ShortcutCenter.shared.resumeAfterRecording()
    }

    private func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        onCapture = nil
        ShortcutCenter.shared.resumeAfterRecording()
    }

    private func consume(keyCode: UInt16, modifierFlags: UInt) -> Bool {
        guard let target = recording else { return false }
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
            .intersection(.deviceIndependentFlagsMask)
        if keyCode == UInt16(kVK_Escape) {
            cancel()
            return true
        }
        if flags.isEmpty, [UInt16(kVK_Delete), UInt16(kVK_ForwardDelete)].contains(keyCode) {
            error = nil
            onCapture?(target, nil)
            finish()
            return true
        }

        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers != 0 else {
            error = "Add at least one modifier. Press Escape to cancel."
            return true
        }
        error = nil
        onCapture?(target, KeyCombo(keyCode: UInt32(keyCode), modifiers: modifiers))
        finish()
        return true
    }
}
