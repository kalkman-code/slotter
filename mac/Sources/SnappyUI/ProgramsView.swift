import AppKit
import DeskTheme
import SnappyKit
import SwiftUI

struct ProgramsView: View {
    @Bindable var model: SettingsModel
    let onClose: () -> Void

    @State private var selection: UUID?
    @State private var editing: Program?
    @State private var editingIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Programs")
                    .font(.system(size: Theme.Size.title, weight: .semibold))
                    .foregroundStyle(Color(theme: Theme.text))
                Text("Define an app once. Every workspace that uses it stays in sync.")
                    .font(.system(size: Theme.Size.body))
                    .foregroundStyle(Color(theme: Theme.dim))
            }
            .padding(20)

            Divider().overlay(Color(theme: Theme.rule))

            if model.programs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No programs yet.")
                        .font(.system(size: Theme.Size.body, weight: .medium))
                        .foregroundStyle(Color(theme: Theme.text))
                    Text("Choose Add program to define one.")
                        .font(.system(size: Theme.Size.small))
                        .foregroundStyle(Color(theme: Theme.dim))
                }
                .padding(20)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.programs.enumerated()), id: \.element.id) { index, program in
                            row(program, index: index)
                        }
                    }
                }
            }

            DeskCommitBar {
                HStack(spacing: 8) {
                    SnappyButton(title: "Add program", glyph: "add") {
                        editingIndex = nil
                        editing = Program(name: "", path: "")
                    }
                    SnappyButton(title: "Edit", glyph: "edit", enabled: selectedIndex != nil) { beginEdit() }
                    SnappyButton(title: "Remove", glyph: "remove", style: .quietDanger, enabled: selectedIndex != nil) {
                        guard let index = selectedIndex else { return }
                        let program = model.programs[index]
                        let orphans = model.zoneCount(using: program.name)
                        let detail = orphans == 0
                            ? "No zones use it."
                            : (orphans == 1 ? "1 zone will lose its program." : "\(orphans) zones will lose their program.")
                        model.confirm(ConfirmRequest(
                            heading: "Remove “\(program.name)”?",
                            body: detail,
                            confirmTitle: "Remove program",
                            danger: true)) {
                            model.removeProgram(at: index)
                            selection = nil
                        }
                    }
                }
            } trailing: {
                SnappyButton(title: "Done", style: .primary, action: onClose)
            }
        }
        .frame(width: 620, height: 460)
        .background(Color(theme: Theme.bg))
        .sheet(item: $editing) { program in
            ProgramEditView(program: program,
                            existingIndex: editingIndex,
                            model: model) { editing = nil }
        }
        .sheet(item: $model.pendingConfirm) { pending in
            ConfirmView(request: pending.request,
                        onConfirm: {
                            let action = pending.action
                            model.pendingConfirm = nil
                            action()
                        },
                        onCancel: { model.pendingConfirm = nil })
        }
    }

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return model.programs.firstIndex { $0.id == selection }
    }

    private func beginEdit() {
        guard let index = selectedIndex else { return }
        editingIndex = index
        editing = model.programs[index]
    }

    private func row(_ program: Program, index: Int) -> some View {
        let selected = program.id == selection
        return HStack(spacing: 10) {
            Image(systemName: Sym.name("program"))
                .font(.system(size: 12))
                .foregroundStyle(Color(theme: selected ? Theme.accent : Theme.dim))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(program.name)
                    .font(.system(size: Theme.Size.body, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Color(theme: Theme.text))
                Text(program.arguments.isEmpty ? program.path : "\(program.path)  \(program.arguments)")
                    .font(.system(size: Theme.Size.micro))
                    .foregroundStyle(Color(theme: Theme.dim))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background(Color(theme: selected ? Theme.soft : .clear))
        .contentShape(Rectangle())
        .onTapGesture { selection = program.id }
        .onTapGesture(count: 2) {
            selection = program.id
            editingIndex = index
            editing = program
        }
    }
}

struct ProgramEditView: View {
    @State var program: Program
    let existingIndex: Int?
    @Bindable var model: SettingsModel
    let onClose: () -> Void

    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existingIndex == nil ? "Add program" : "Edit program")
                .font(.system(size: Theme.Size.large, weight: .semibold))
                .foregroundStyle(Color(theme: Theme.text))

            field("Name") {
                TextField("", text: $program.name).textFieldStyle(.roundedBorder)
            }
            field("Application") {
                HStack(spacing: 8) {
                    TextField("", text: $program.path).textFieldStyle(.roundedBorder)
                    SnappyButton(title: "Browse…", glyph: "browse", action: browse)
                }
            }
            field("Arguments") {
                TextField("", text: $program.arguments).textFieldStyle(.roundedBorder)
            }

            Toggle("Launch a new instance", isOn: $program.newInstance)
                .font(.system(size: Theme.Size.body))
                .foregroundStyle(Color(theme: Theme.text))

            if let error {
                Text(error)
                    .font(.system(size: Theme.Size.small))
                    .foregroundStyle(Color(theme: Theme.danger))
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                SnappyButton(title: "Cancel", action: onClose).keyboardShortcut(.cancelAction)
                SnappyButton(title: "Save program", style: .primary, action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520, height: 330)
        .background(Color(theme: Theme.bg))
    }

    @ViewBuilder
    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: Theme.Size.micro, weight: .semibold))
                .foregroundStyle(Color(theme: Theme.dim))
            content()
        }
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
            program.path = url.path
            if program.name.trimmingCharacters(in: .whitespaces).isEmpty {
                program.name = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func save() {
        let existing = existingIndex.map { model.programs[$0] }
        if let message = Validate.programName(program.name, excluding: existing, in: model.programs) {
            error = message
            return
        }
        if let message = Validate.programPath(program.path) {
            error = message
            return
        }

        var cleaned = program
        cleaned.name = program.name.trimmingCharacters(in: .whitespaces)
        cleaned.path = program.path.trimmingCharacters(in: .whitespaces)

        if let index = existingIndex {
            let oldName = model.programs[index].name
            model.programs[index] = cleaned
            if oldName != cleaned.name { model.renameProgram(at: index, to: cleaned.name) }
            model.markDirty()
        } else {
            model.programs.append(cleaned)
            model.markDirty()
        }
        onClose()
    }
}
