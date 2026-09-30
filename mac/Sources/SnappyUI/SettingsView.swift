import AppKit
import DeskTheme
import SnappyKit
import SwiftUI

struct NamePrompt: Identifiable {
    enum Kind { case add, rename }
    let id = UUID()
    var kind: Kind
    var text: String
}

struct SettingsView: View {
    @Bindable var model: SettingsModel
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var prompt: NamePrompt?
    @State private var showingPrograms: Bool

    init(model: SettingsModel, onSave: @escaping () -> Void, onCancel: @escaping () -> Void,
         openPrograms: Bool = false) {
        self.model = model
        self.onSave = onSave
        self.onCancel = onCancel
        self._showingPrograms = State(initialValue: openPrograms)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Color(theme: Theme.rule))

            HStack(spacing: 0) {
                WorkspaceListView(model: model,
                                  onAdd: { prompt = NamePrompt(kind: .add, text: "") },
                                  onRename: { prompt = NamePrompt(kind: .rename,
                                                                  text: model.selectedWorkspace?.name ?? "") })
                    .frame(width: 268)

                Divider().overlay(Color(theme: Theme.rule))

                MonitorCanvasView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().overlay(Color(theme: Theme.rule))

                ZoneInspectorView(model: model,
                                  onManagePrograms: { showingPrograms = true },
                                  onConfirmPreset: applyPreset)
                    .frame(width: 300)
            }

            Divider().overlay(Color(theme: Theme.rule))
            bottomBar
        }
        .frame(minWidth: 1100, minHeight: 800)
        .background(Color(theme: Theme.bg))
        .sheet(item: $prompt) { active in
            NamePromptView(prompt: active, model: model) { prompt = nil }
        }
        .sheet(isPresented: $showingPrograms) {
            ProgramsView(model: model) { showingPrograms = false }
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

    private var topBar: some View {
        HStack(spacing: 14) {
            Image(nsImage: Mark.appIcon(side: 40))
                .resizable()
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Workspace designer")
                    .font(.system(size: Theme.Size.title, weight: .semibold))
                    .foregroundStyle(Color(theme: Theme.text))
                Text("Arrange apps once, then launch the whole desk from the menu bar.")
                    .font(.system(size: Theme.Size.body))
                    .foregroundStyle(Color(theme: Theme.dim))
            }

            Spacer()

            if !AX.isTrusted {
                Label("Accessibility not granted", systemImage: Sym.name("kill"))
                    .font(.system(size: Theme.Size.small, weight: .medium))
                    .foregroundStyle(Color(theme: Theme.danger))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(theme: Theme.bg))
    }

    private var bottomBar: some View {
        DeskCommitBar {
            Toggle("Start at login", isOn: Binding(
                get: { model.startAtLogin },
                set: { model.startAtLogin = $0; model.markDirty() }))
                .font(.system(size: Theme.Size.body))
                .foregroundStyle(Color(theme: Theme.text))

            Text("Changes apply when you save.")
                .font(.system(size: Theme.Size.small))
                .foregroundStyle(Color(theme: Theme.dim))
        } trailing: {
            SnappyButton(title: "Cancel", action: onCancel).keyboardShortcut(.cancelAction)
            SnappyButton(title: "Save changes", glyph: "save", style: .primary, action: onSave)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func applyPreset(_ preset: LayoutPreset) {
        let existing = model.selectedWorkspace?.zones.contains { zone in
            DisplayRegistry.resolve(zone.monitor)?.id == model.selectedDisplay?.id
        } ?? false

        guard existing else {
            model.applyPreset(preset)
            return
        }
        model.confirm(ConfirmRequest(
            heading: "Replace this monitor's zones?",
            body: "“\(preset.name)” replaces every zone currently on this monitor.",
            confirmTitle: "Replace zones")) {
            model.applyPreset(preset)
        }
    }
}

struct NamePromptView: View {
    @State var prompt: NamePrompt
    @Bindable var model: SettingsModel
    let onClose: () -> Void

    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(prompt.kind == .add ? "Add workspace" : "Rename workspace")
                .font(.system(size: Theme.Size.large, weight: .semibold))
                .foregroundStyle(Color(theme: Theme.text))

            TextField("", text: $prompt.text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)

            if let error {
                Text(error)
                    .font(.system(size: Theme.Size.small))
                    .foregroundStyle(Color(theme: Theme.danger))
            }

            HStack {
                Spacer()
                SnappyButton(title: "Cancel", action: onClose).keyboardShortcut(.cancelAction)
                SnappyButton(title: prompt.kind == .add ? "Add" : "Rename",
                             style: .primary, action: commit).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(Color(theme: Theme.bg))
    }

    private func commit() {
        let excluding = prompt.kind == .rename ? model.selectedWorkspace : nil
        if let message = Validate.workspaceName(prompt.text, excluding: excluding, in: model.workspaces) {
            error = message
            return
        }
        let name = prompt.text.trimmingCharacters(in: .whitespaces)
        if prompt.kind == .add {
            model.addWorkspace(named: name)
        } else {
            model.renameSelectedWorkspace(to: name)
        }
        onClose()
    }
}
