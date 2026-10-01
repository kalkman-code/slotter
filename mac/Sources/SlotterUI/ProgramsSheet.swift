import AppKit
import SlotterKit
import SwiftUI

private let P = T.palette

/// Programs: a top-anchored sheet over the dimmed designer. Edits are live and staged with
/// everything else, so Done only closes it.
struct ProgramsSheet: View {
    @Bindable var model: SettingsModel
    let layout: DesignerLayout

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Programs").font(T.font(T.type.heading, .extraBold)).tracking(-0.2).foregroundStyle(P.ink)
                Text("Defined once, picked by every zone. Renaming one renames it in every zone that uses it.")
                    .font(T.font(T.type.small)).foregroundStyle(P.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, layout.narrow ? 16 : 22)
            .padding(.top, layout.narrow ? 14 : 18)
            .padding(.bottom, layout.narrow ? 10 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(P.rule).frame(height: 1) }

            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }
            }

            HStack(spacing: 8) {
                Button { model.addProgram() } label: {
                    HStack(spacing: 6) { Icon(kind: .plus, size: 12); Text("Add program") }
                }
                .buttonStyle(InkButtonStyle())
                Button("Remove") { model.removeSelectedProgram() }
                    .buttonStyle(InkButtonStyle(kind: .danger))
                    .disabled(model.selectedProgramID == nil)
                Spacer(minLength: 0)
                Button("Done") { model.showingPrograms = false }
                    .buttonStyle(InkButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, layout.narrow ? 16 : 22)
            .padding(.vertical, layout.narrow ? 10 : 12)
            .overlay(alignment: .top) { Rectangle().fill(P.rule).frame(height: 1) }
        }
        .background(P.sheet)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: T.radii.sheet, bottomTrailingRadius: T.radii.sheet))
        .overlay {
            SheetEdge(radius: T.radii.sheet).stroke(P.fieldBorder, lineWidth: 1)
        }
        .floatingShadow()
        .onExitCommand { model.showingPrograms = false }
    }

    @ViewBuilder private var content: some View {
        if layout.narrow {
            VStack(spacing: 0) {
                WrapLayout(spacing: 4, lineSpacing: 4) {
                    ForEach(model.programs) { program in ProgramRow(model: model, program: program, compact: true) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { Rectangle().fill(P.rule).frame(height: 1) }
                form.padding(.horizontal, 16).padding(.vertical, 12)
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 2) {
                    ForEach(model.programs) { program in ProgramRow(model: model, program: program, compact: false) }
                }
                .padding(8)
                .frame(width: 200, alignment: .top)
                Rectangle().fill(P.rule).frame(width: 1)
                form.padding(.horizontal, 22).padding(.vertical, 16)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var form: some View {
        if let program = model.programs.first(where: { $0.id == model.selectedProgramID }) {
            ProgramForm(model: model, program: program)
                .id(program.id)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            Text("No programs yet. Add one to give zones something to launch.")
                .font(T.font(T.type.small))
                .foregroundStyle(P.ink2)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// The sheet's outline: sides and bottom, no top edge, since it hangs from the title bar.
private struct SheetEdge: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect.insetBy(dx: 0.5, dy: 0)
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - radius))
        path.addArc(center: CGPoint(x: r.minX + radius, y: r.maxY - radius - 0.5), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        path.addLine(to: CGPoint(x: r.maxX - radius, y: r.maxY - 0.5))
        path.addArc(center: CGPoint(x: r.maxX - radius, y: r.maxY - radius - 0.5), radius: radius,
                    startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return path
    }
}

private struct ProgramRow: View {
    @Bindable var model: SettingsModel
    let program: Program
    let compact: Bool
    @State private var hovering = false

    var body: some View {
        let selected = program.id == model.selectedProgramID
        let uses = model.zoneUses(of: program).count
        Button { model.selectedProgramID = program.id } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(program.name)
                    .font(T.font(T.type.tab, selected ? .extraBold : .semibold))
                    .lineLimit(1)
                if !compact {
                    Spacer(minLength: 0)
                    Text(uses == 0 ? "unused" : uses == 1 ? "1 zone" : "\(uses) zones")
                        .font(T.font(T.type.label))
                        .foregroundStyle(P.ink3)
                        .fixedSize()
                }
            }
            .foregroundStyle(selected || hovering ? P.ink : P.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, compact ? 6 : 8)
            .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: T.radii.field).fill(selected || hovering ? P.hover : .clear))
            .overlay(alignment: .leading) {
                if selected {
                    UnevenRoundedRectangle(topLeadingRadius: T.radii.field, bottomLeadingRadius: T.radii.field)
                        .fill(P.selection).frame(width: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .focusRing()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ProgramForm: View {
    @Bindable var model: SettingsModel
    let program: Program
    @State private var name: String
    @State private var nameError: String?
    @FocusState private var nameFocused: Bool
    @FocusState private var pathFocused: Bool
    @FocusState private var argsFocused: Bool

    init(model: SettingsModel, program: Program) {
        self.model = model
        self.program = program
        _name = State(initialValue: program.name)
    }

    var body: some View {
        let path = program.path.trimmingCharacters(in: .whitespaces)
        let uses = model.zoneUses(of: program)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Name")
                field(InkTextField(text: $name, font: T.font(T.type.body), focus: $nameFocused), invalid: nameError != nil)
                if let nameError { hint(nameError, error: true) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Executable or app")
                HStack(spacing: 6) {
                    field(InkTextField(text: binding(\.path), font: T.font(T.type.body), focus: $pathFocused),
                          invalid: path.isEmpty)
                    Button("Browse…", action: browse).buttonStyle(InkButtonStyle(height: 34))
                }
                if path.isEmpty {
                    hint("Choose an application. Saving waits for one.", error: true)
                } else if !FileManager.default.fileExists(atPath: path) {
                    hint("Nothing exists at that path.", error: true)
                } else {
                    hint("An .app, such as /Applications/Safari.app, or an executable.", error: false)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Arguments, optional")
                field(InkTextField(text: binding(\.arguments), font: T.font(T.type.body), placeholder: "--new-window",
                                   focus: $argsFocused), invalid: false)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch a new instance").font(T.font(T.type.body, .bold)).foregroundStyle(P.ink)
                    Text("Opens another copy even when it is already running.")
                        .font(T.font(T.type.small)).foregroundStyle(P.ink2)
                }
                Spacer(minLength: 0)
                SwitchPill(isOn: program.newInstance) {
                    model.updateProgram(program.id) { $0.newInstance.toggle() }
                }
                .accessibilityLabel("Launch a new instance")
            }
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Used by")
                if uses.isEmpty {
                    Text("No zone yet.").font(T.font(T.type.small)).foregroundStyle(P.ink2)
                } else {
                    WrapLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(uses, id: \.self) { use in
                            Text(use)
                                .font(T.font(T.type.small))
                                .foregroundStyle(P.ink2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .overlay(RoundedRectangle(cornerRadius: T.radii.chip).strokeBorder(P.fieldBorder, lineWidth: 1))
                                .fixedSize()
                        }
                    }
                }
            }
        }
        .onChange(of: name) { _, value in
            guard value != program.name else { nameError = nil; return }
            nameError = model.renameProgram(program.id, to: value)
        }
        .onChange(of: nameFocused) { _, focused in
            if !focused { name = program.name; nameError = nil }
        }
        .onChange(of: model.focusRequest) { _, request in
            guard request == .programPath(program.id) else { return }
            pathFocused = true
            model.focusRequest = nil
        }
    }

    private func binding(_ key: WritableKeyPath<Program, String>) -> Binding<String> {
        Binding(get: { program[keyPath: key] },
                set: { value in model.updateProgram(program.id) { $0[keyPath: key] = value } })
    }

    private func field(_ input: some View, invalid: Bool) -> some View {
        input
            .padding(.horizontal, 10)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .box(invalid: invalid)
    }

    private func hint(_ text: String, error: Bool) -> some View {
        Text(text)
            .font(T.font(T.type.label, error ? .semibold : .regular))
            .foregroundStyle(error ? P.error : P.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application, .unixExecutable]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                model.updateProgram(program.id) { $0.path = url.path }
                if program.name.hasPrefix("New program") {
                    name = url.deletingPathExtension().lastPathComponent
                }
            }
        }
    }
}
