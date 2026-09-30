import AppKit
import SwiftUI

public enum SnappyButtonStyle: Sendable {
    case primary
    case secondary
    case danger
    case quietDanger
}

/// Snappy's button, restyled to Desk.Button / Desk.Button.Primary / Desk.Button.Ghost (see
/// ykit/wpf/Desk.xaml section "buttons"): a secondary button is a constant field-raised chip
/// whose border — not its fill — picks up the accent on hover or focus; a filled button (primary,
/// danger) does not dim on hover, only its content dims while pressed; a quiet/ghost button stays
/// transparent and only its border and text intensify on hover. Kept as Snappy's own component
/// (not moved into DeskTheme) because `quietDanger`, `iconOnly` and `fills` are Snappy-specific
/// shapes, not part of the shared design system.
public struct SnappyButton: View {
    let title: String
    var glyph: String?
    var style: SnappyButtonStyle
    var enabled: Bool
    var iconOnly: Bool
    var fills: Bool
    let action: () -> Void

    public init(title: String,
                glyph: String? = nil,
                style: SnappyButtonStyle = .secondary,
                enabled: Bool = true,
                iconOnly: Bool = false,
                fills: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.glyph = glyph
        self.style = style
        self.enabled = enabled
        self.iconOnly = iconOnly
        self.fills = fills
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            content
        }
        .buttonStyle(DeskChipButtonStyle(style: style, iconOnly: iconOnly, fills: fills))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(iconOnly ? title : "")
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var content: some View {
        if iconOnly {
            Image(systemName: Sym.name(glyph ?? "add"))
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28)
        } else {
            HStack(spacing: 6) {
                if let glyph {
                    Image(systemName: Sym.name(glyph))
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: Theme.Size.body, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 14)
        }
    }
}

private struct DeskChipButtonStyle: ButtonStyle {
    let style: SnappyButtonStyle
    let iconOnly: Bool
    let fills: Bool

    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 28)
            .frame(maxWidth: fills ? .infinity : nil)
            .foregroundStyle(foreground)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(border, lineWidth: 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var foreground: Color {
        switch style {
        case .primary, .danger: return Color(theme: Theme.onAccent)
        case .quietDanger: return Color(theme: Theme.danger)
        case .secondary: return Color(theme: Theme.text)
        }
    }

    /// Constant per style — filled buttons do not dim on hover, matching Desk.Button.Primary,
    /// which has no hover trigger of its own.
    private var background: Color {
        switch style {
        case .primary: return Color(theme: Theme.accentFill)
        case .danger: return Color(theme: Theme.dangerFill)
        case .quietDanger: return .clear
        case .secondary: return Color(theme: Theme.hover)
        }
    }

    /// The one thing that moves on hover for an unfilled button: the border (and, for the ghost
    /// styles, the text) picks up the accent or danger tint. Matches Desk.Button's IsMouseOver
    /// trigger, which only ever touches BorderBrush.
    private var border: Color {
        switch style {
        case .primary, .danger: return .clear
        case .quietDanger: return Color(theme: Theme.danger).opacity(hovering ? 0.9 : 0.45)
        case .secondary: return Color(theme: hovering ? Theme.accent : Theme.rule)
        }
    }
}
