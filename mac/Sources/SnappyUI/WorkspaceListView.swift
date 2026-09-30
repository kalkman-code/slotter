import DeskTheme
import SnappyKit
import SwiftUI

struct WorkspaceListView: View {
    @Bindable var model: SettingsModel
    let onAdd: () -> Void
    let onRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DeskEyebrow("Workspaces")
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

            if model.workspaces.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("No workspaces yet.")
                        .font(.system(size: Theme.Size.body, weight: .medium))
                        .foregroundStyle(Color(theme: Theme.text))
                    Text("Add one, then choose a preset to lay out its zones.")
                        .font(.system(size: Theme.Size.small))
                        .foregroundStyle(Color(theme: Theme.dim))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.workspaces) { workspace in
                            row(workspace)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }

            Divider().overlay(Color(theme: Theme.rule))

            HStack(spacing: 8) {
                SnappyButton(title: "Add workspace", glyph: "add", fills: true, action: onAdd)
                SnappyButton(title: "Rename workspace", glyph: "rename",
                             enabled: model.selectedWorkspace != nil, iconOnly: true, action: onRename)
                SnappyButton(title: "Remove workspace", glyph: "remove", style: .quietDanger,
                             enabled: model.selectedWorkspace != nil, iconOnly: true) {
                    guard let workspace = model.selectedWorkspace else { return }
                    model.confirm(ConfirmRequest(
                        heading: "Remove “\(workspace.name)”?",
                        body: workspace.zones.isEmpty
                            ? "It has no zones yet. This cannot be undone."
                            : "Its \(workspace.zones.count) zones go with it. This cannot be undone.",
                        confirmTitle: "Remove workspace",
                        danger: true)) {
                        model.removeSelectedWorkspace()
                    }
                }
            }
            .padding(14)
        }
        .background(Color(theme: Theme.surface))
    }

    private func row(_ workspace: Workspace) -> some View {
        let selected = workspace.id == model.selectedWorkspaceID
        return HStack(spacing: 11) {
            Image(systemName: Sym.name(selected ? "set" : "workspace"))
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(Color(theme: selected ? Theme.accent : Theme.dim))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(workspace.name)
                    .font(.system(size: Theme.Size.body, weight: selected ? .semibold : .regular))
                    .foregroundStyle(Color(theme: selected ? Theme.accent : Theme.text))
                    .lineLimit(1)
                Text(workspace.zones.count == 1 ? "1 zone" : "\(workspace.zones.count) zones")
                    .font(.system(size: Theme.Size.micro))
                    .foregroundStyle(Color(theme: Theme.dim))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(theme: selected ? Theme.zoneFillSelected : .clear)))
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedWorkspaceID = workspace.id
            model.selectedZoneIndex = nil
        }
    }
}
