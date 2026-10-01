import AppKit
import SlotterKit
import SwiftUI

private let P = T.palette

/// The inspector: a drawer under the desk with two tabs on its top edge and Save beside them.
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
                }
                Spacer(minLength: 0)
            }
            .frame(height: 46, alignment: .bottom)
            .overlay(alignment: .trailing) { CommitBar(model: model, narrow: layout.narrow).padding(.top, 2) }
            .padding(.leading, layout.narrow ? 12 : 24)
            .padding(.trailing, layout.narrow ? 12 : 16)
            .zIndex(1)

            if model.face == .zone, let zone, let workspace = model.selectedWorkspace {
                ZoneFace(model: model, zone: zone, workspace: workspace, layout: layout)
                    .modifier(Face(narrow: layout.stacked))
            } else if model.face == .settings {
                SettingsFace(model: model, layout: layout)
                    .modifier(Face(narrow: layout.stacked))
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
                .fixedSize()
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

private struct CommitBar: View {
    @Bindable var model: SettingsModel
    let narrow: Bool
    @State private var hoveringFault = false

    var body: some View {
        let faults = model.faults
        HStack(spacing: 8) {
            if !faults.isEmpty {
                Button { model.gotoFirstFault() } label: {
                    HStack(spacing: 7) {
                        Icon(kind: .warn, size: 14)
                        Text(narrow ? "\(faults.count) to fix"
                             : "\(faults.count) problem\(faults.count == 1 ? " stops" : "s stop") saving")
                    }
                    .font(T.font(T.type.small, .semibold))
                    .foregroundStyle(P.error)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: T.radii.field).fill(hoveringFault ? P.errorGround : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveringFault = $0 }
                .focusRing()
                .help(faults.map(\.message).joined(separator: "\n"))
            } else if model.dirty {
                HStack(spacing: 7) {
                    Circle().fill(P.ink).frame(width: 8, height: 8)
                    Text(narrow ? "Unsaved" : "Unsaved changes")
                }
                .font(T.font(T.type.small))
                .foregroundStyle(P.ink2)
                .padding(.horizontal, 6)
            } else if !narrow || model.saved {
                Text(model.saved ? "Saved" : "No changes")
                    .font(T.font(T.type.small))
                    .foregroundStyle(P.ink2)
                    .padding(.horizontal, 6)
            }

            Button("Cancel") { model.cancel() }
                .buttonStyle(InkButtonStyle(kind: .quiet))
                .disabled(!model.dirty)

            Button { model.save() } label: { Text(narrow ? "Save" : "Save changes") }
                .buttonStyle(InkButtonStyle(kind: .primary, blocked: !model.dirty || !faults.isEmpty))
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityHint(faults.isEmpty ? "" : "Save is blocked: " + faults.map(\.message).joined(separator: "; "))
        }
        .fixedSize()
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

    private var zoneIcons: some View {
        HStack(spacing: 4) {
            Button { model.splitSelectedZone(vertical: true) } label: { Icon(kind: .splitV) }
                .buttonStyle(IconButtonStyle()).help("Split vertically").accessibilityLabel("Split vertically")
            Button { model.splitSelectedZone(vertical: false) } label: { Icon(kind: .splitH) }
                .buttonStyle(IconButtonStyle()).help("Split horizontally").accessibilityLabel("Split horizontally")
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
                Button { model.splitSelectedZone(vertical: false) } label: {
                    HStack(spacing: 6) { Icon(kind: .splitH); Text("Split horizontally") }
                }
                .buttonStyle(InkButtonStyle())
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
        return WrapLayout(spacing: 10, lineSpacing: 4) {
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
    }

    private func nowText(_ key: String) -> String {
        "Now: " + (model.presetMatch(on: key, in: workspace)?.name ?? "custom")
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
            if !compact { Eyebrow("Position and size, % of work area").padding(.bottom, 6) }
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
        case .empty: lead = "Width and Height must be more than 0%."
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
        _text = State(initialValue: Percent.text(raw))
    }

    private var value: Double {
        switch field {
        case .x: zone.x
        case .y: zone.y
        case .w: zone.w
        case .h: zone.h
        }
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
            Text("%")
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
        .onChange(of: value) { _, newValue in if !focused { text = Percent.text(newValue) } }
        .onChange(of: zone.id) { _, _ in text = Percent.text(value) }
        .onChange(of: text) { _, newValue in
            // The field shows one decimal of a value stored to two; only a real edit may write
            // back, or merely showing 33.3 would overwrite 33.33.
            guard focused, newValue != Percent.text(value),
                  let parsed = Double(newValue.replacingOccurrences(of: ",", with: ".")) else { return }
            if abs(parsed - value) > 0.001 { model.setValue(field, parsed) }
        }
        .onChange(of: focused) { _, isFocused in if !isFocused { text = Percent.text(value) } }
        .onChange(of: model.focusRequest) { _, request in
            guard request == .field(field) else { return }
            focused = true
            model.focusRequest = nil
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), percent")
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
                shortcuts
                accessibility
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Slotter settings").font(T.font(T.type.heading, .extraBold)).tracking(-0.2).foregroundStyle(P.ink)
                    login
                }
                .padding(.trailing, 24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                Rectangle().fill(P.rule).frame(width: 1)
                shortcuts
                    .padding(.horizontal, 24)
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

    private var shortcuts: some View {
        let status = model.status
        return VStack(alignment: .leading, spacing: 4) {
            Text("Snap shortcuts").font(T.font(T.type.body, .bold)).foregroundStyle(P.ink)
            HStack(spacing: 6) {
                Kbd("⌃ ⌥ ←")
                Text("left half, and \(max(0, status.shortcutCount - 1)) more")
                    .font(T.font(T.type.small)).foregroundStyle(P.ink2)
            }
            if !status.accessibilityTrusted {
                StateLine(ok: false, text: "Off until Accessibility is granted.")
            } else if status.shortcutFailures > 0 {
                StateLine(ok: false, text: "\(status.shortcutFailures) unavailable: another app holds \(status.shortcutFailures == 1 ? "it" : "them"). Rebind in profiles.ini.")
            } else {
                StateLine(ok: true, text: "Ready. Halves, thirds and corners from anywhere.")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility permission").font(T.font(T.type.body, .bold)).foregroundStyle(P.ink)
                if model.status.accessibilityTrusted {
                    StateLine(ok: true, text: "Granted. Slotter can move windows.")
                } else {
                    StateLine(ok: false, text: "Not granted. Slotter cannot move windows until it is.")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            WrapLayout(spacing: 6, lineSpacing: 6) {
                if !model.status.accessibilityTrusted {
                    Button("Open System Settings") { model.actions.openAccessibilitySettings() }
                        .buttonStyle(InkButtonStyle())
                }
                Button("Manage programs…") { model.showingPrograms = true }
                    .buttonStyle(InkButtonStyle(kind: .quiet))
            }
        }
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
