import DeskTheme
import SnappyKit
import SwiftUI

struct PercentField: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void

    @State private var text = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: Theme.Size.small, weight: .medium))
                .foregroundStyle(Color(theme: Theme.dim))
                .frame(width: 14, alignment: .leading)

            HStack(spacing: 0) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.Size.body).monospacedDigit())
                    .foregroundStyle(Color(theme: Theme.text))
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 9)
                    .focused($editing)
                    .onSubmit(commit)
                    .onChange(of: editing) { _, focused in if !focused { commit() } }

                Text("%")
                    .font(.system(size: Theme.Size.small))
                    .foregroundStyle(Color(theme: Theme.dim))
                    .padding(.trailing, 8)

                Stepper("", value: Binding(
                    get: { value },
                    set: { onChange(clamp($0)) }), in: range, step: 0.25)
                    .labelsHidden()
                    .padding(.trailing, 3)
            }
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(theme: Theme.field))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(theme: editing ? Theme.accent : Theme.rule),
                                      lineWidth: editing ? 1.5 : 1)))
        }
        .onAppear { text = format(value) }
        .onChange(of: value) { _, newValue in if !editing { text = format(newValue) } }
    }

    private func commit() {
        guard let parsed = Double(text.replacingOccurrences(of: ",", with: ".")) else {
            text = format(value)
            return
        }
        let clamped = clamp(parsed)
        text = format(clamped)
        onChange(clamped)
    }

    private func clamp(_ raw: Double) -> Double {
        let rounded = (raw * 100).rounded() / 100
        return min(max(rounded, range.lowerBound), range.upperBound)
    }

    private func format(_ raw: Double) -> String {
        raw == raw.rounded() ? String(Int(raw)) : String(format: "%.2f", raw)
    }
}

struct PresetMenu: View {
    let enabled: Bool
    let onPick: (LayoutPreset) -> Void

    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(PresetCatalog.all) { preset in
                Button(preset.name) { onPick(preset) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: Sym.name("set"))
                    .font(.system(size: 11, weight: .semibold))
                Text("Apply a preset")
                    .font(.system(size: Theme.Size.body, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(theme: Theme.dim))
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .foregroundStyle(Color(theme: Theme.text))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(theme: hovering ? Theme.hover : Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color(theme: Theme.rule), lineWidth: 1)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// The detail of whatever is currently selected — the monitor, and its selected zone — so it
/// wears Desk's Inspector treatment: a 3px accent left border the full height of the pane. This
/// pane is a full-height docked sidebar rather than a floating card, so it keeps its flush square
/// edges and skips the panel's rounding and full border; only the accent stripe, which is the
/// component's whole point, comes across.
struct ZoneInspectorView: View {
    @Bindable var model: SettingsModel
    let onManagePrograms: () -> Void
    let onConfirmPreset: (LayoutPreset) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color(desk: Desk.accent)).frame(width: 3)
            inspectorBody
        }
        .background(Color(theme: Theme.surface))
    }

    private var inspectorBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("Monitor") {
                    Text(model.selectedDisplay?.name ?? "No display")
                        .font(.system(size: Theme.Size.body, weight: .semibold))
                        .foregroundStyle(Color(theme: Theme.text))
                        .lineLimit(1)

                    PresetMenu(enabled: model.selectedWorkspace != nil, onPick: onConfirmPreset)

                    SnappyButton(title: "Reset monitor", glyph: "reset", style: .quietDanger,
                                 enabled: model.selectedWorkspace != nil, fills: true) {
                        model.confirm(ConfirmRequest(
                            heading: "Remove every zone on this monitor?",
                            body: "The workspace keeps its zones on other monitors.",
                            confirmTitle: "Remove zones",
                            danger: true)) {
                            model.resetSelectedDisplay()
                        }
                    }
                }

                Divider().overlay(Color(theme: Theme.rule))

                if let zone = model.selectedZone {
                    section("Zone \((model.selectedZoneIndex ?? 0) + 1)") {
                        VStack(spacing: 7) {
                            PercentField(label: "X", value: zone.x, range: 0...99) { value in
                                model.updateSelectedZone { $0.x = value }
                            }
                            PercentField(label: "Y", value: zone.y, range: 0...99) { value in
                                model.updateSelectedZone { $0.y = value }
                            }
                            PercentField(label: "W", value: zone.w, range: 1...100) { value in
                                model.updateSelectedZone { $0.w = value }
                            }
                            PercentField(label: "H", value: zone.h, range: 1...100) { value in
                                model.updateSelectedZone { $0.h = value }
                            }
                        }
                        Text("Percentages of the monitor's visible area.")
                            .font(.system(size: Theme.Size.micro))
                            .foregroundStyle(Color(theme: Theme.dim))
                    }

                    section("Split") {
                        HStack(spacing: 8) {
                            SnappyButton(title: "Vertical", glyph: "splitv",
                                         enabled: zone.isSplittableHorizontally, fills: true) {
                                model.splitSelectedZone(vertical: true)
                            }
                            SnappyButton(title: "Horizontal", glyph: "splith",
                                         enabled: zone.isSplittableVertically, fills: true) {
                                model.splitSelectedZone(vertical: false)
                            }
                        }
                    }

                    section("Program") {
                        Picker("", selection: Binding(
                            get: { zone.program ?? "" },
                            set: { value in model.updateSelectedZone { $0.program = value.isEmpty ? nil : value } })) {
                            Text("No program — manual snap target").tag("")
                            Divider()
                            ForEach(model.programs) { program in
                                Text(program.name).tag(program.name)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)

                        SnappyButton(title: "Manage programs…", glyph: "program",
                                     fills: true, action: onManagePrograms)
                    }

                    Divider().overlay(Color(theme: Theme.rule))

                    SnappyButton(title: "Delete zone", glyph: "remove", style: .quietDanger, fills: true) {
                        model.removeSelectedZone()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("No zone selected")
                            .font(.system(size: Theme.Size.body, weight: .semibold))
                            .foregroundStyle(Color(theme: Theme.text))
                        Text("Click a zone on the canvas to edit it, or apply a preset to create some.")
                            .font(.system(size: Theme.Size.small))
                            .foregroundStyle(Color(theme: Theme.dim))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    SnappyButton(title: "Manage programs…", glyph: "program",
                                 fills: true, action: onManagePrograms)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DeskEyebrow(title)
            content()
        }
    }
}
