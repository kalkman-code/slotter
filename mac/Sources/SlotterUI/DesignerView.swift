import SlotterKit
import SwiftUI

private let P = T.palette

/// The workspace designer, Slotter's one window.
public struct DesignerView: View {
    @Bindable var model: SettingsModel

    public init(model: SettingsModel) {
        self.model = model
    }

    public var body: some View {
        GeometryReader { proxy in
            let layout = DesignerLayout(width: proxy.size.width, height: proxy.size.height)
            VStack(spacing: 0) {
                TopBar(model: model, layout: layout).zIndex(5)
                DeskView(model: model, layout: layout).zIndex(1)
                DrawerView(model: model, layout: layout).zIndex(3)
            }
            .overlay {
                if model.showingPrograms {
                    Scrim {
                        ProgramsSheet(model: model, layout: layout)
                            .frame(width: layout.narrow ? layout.width - 16 : min(680, layout.width - 32))
                            .frame(maxHeight: layout.height - 24, alignment: .top)
                    }
                }
            }
            .overlay {
                if let pending = model.pendingConfirm {
                    Scrim {
                        ConfirmView(request: pending.request,
                                    onConfirm: {
                                        model.pendingConfirm = nil
                                        pending.action()
                                    },
                                    onCancel: { model.pendingConfirm = nil })
                            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: T.radii.sheet, bottomTrailingRadius: T.radii.sheet))
                            .floatingShadow()
                    }
                }
            }
        }
        .background(P.ground)
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 640, minHeight: 560)
    }
}

/// A flat 74% fill over the window with the sheet hanging from the top. No blur, per the brief.
private struct Scrim<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            P.scrim
                .contentShape(Rectangle())
                .onTapGesture {}
            content
        }
    }
}
