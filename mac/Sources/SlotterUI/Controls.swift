import AppKit
import SwiftUI

private let P = T.palette

// MARK: - Offscreen rendering

/// `ImageRenderer` cannot draw AppKit-backed controls (it paints a placeholder), so a render
/// swaps each text field for its text. Nothing else changes between the app and a render.
public struct StaticRenderKey: EnvironmentKey {
    public static let defaultValue = false
}

public extension EnvironmentValues {
    var staticRender: Bool {
        get { self[StaticRenderKey.self] }
        set { self[StaticRenderKey.self] = newValue }
    }
}

// MARK: - Focus

/// Keyboard focus is a 2px ink ring, never yellow, so it cannot be mistaken for selection.
struct FocusRing: ViewModifier {
    var radius: CGFloat = T.radii.field
    var inset: CGFloat = -2
    @Environment(\.isFocused) private var focused

    func body(content: Content) -> some View {
        content.overlay {
            if focused {
                RoundedRectangle(cornerRadius: radius + 2)
                    .strokeBorder(P.ink, lineWidth: 2)
                    .padding(inset)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func focusRing(radius: CGFloat = T.radii.field) -> some View {
        modifier(FocusRing(radius: radius)).focusEffectDisabled()
    }

    func floatingShadow() -> some View {
        shadow(color: P.shadow, radius: 18, x: 0, y: 14)
    }

    func box(fill: Color = P.field, line: Color = P.fieldBorder, radius: CGFloat = T.radii.field,
             invalid: Bool = false) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay {
                if invalid {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(P.error, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                } else {
                    RoundedRectangle(cornerRadius: radius).strokeBorder(line, lineWidth: 1)
                }
            }
    }

    func dashedBorder(_ color: Color, width: CGFloat = 1, radius: CGFloat) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius)
            .strokeBorder(color, style: StrokeStyle(lineWidth: width, dash: [4, 3])))
    }
}

// MARK: - Buttons

enum InkKind { case primary, secondary, quiet, danger, quietDanger, dashed }

struct InkButtonStyle: ButtonStyle {
    var kind: InkKind = .secondary
    var height: CGFloat = 32
    /// Looks disabled but still takes the click: Save does this so it can jump to the fault.
    var blocked = false

    func makeBody(configuration: Configuration) -> some View {
        InkButtonBody(configuration: configuration, kind: kind, height: height, blocked: blocked)
    }
}

private struct InkButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: InkKind
    let height: CGFloat
    let blocked: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .font(T.font(T.type.body, kind == .primary ? .bold : .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, kind == .dashed ? 10 : 12)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: T.radii.field).fill(fill))
            .overlay { border }
            .contentShape(Rectangle())
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
            .onHover { hovering = $0 }
            .focusRing()
    }

    private var foreground: Color {
        switch kind {
        case .primary: blocked ? P.ink2 : P.onSelection
        case .secondary: P.ink
        case .quiet, .dashed: hovering && enabled ? P.ink : P.ink2
        case .danger, .quietDanger: P.error
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: blocked ? P.disabledFill : P.ink
        case .secondary, .danger: P.field
        case .quiet, .quietDanger, .dashed: .clear
        }
    }

    @ViewBuilder private var border: some View {
        let shape = RoundedRectangle(cornerRadius: T.radii.field)
        switch kind {
        case .primary:
            shape.strokeBorder(blocked ? P.disabledFill : P.ink, lineWidth: 1)
        case .secondary, .danger:
            shape.strokeBorder(hovering && enabled ? P.ink3 : P.fieldBorder, lineWidth: 1)
        case .quiet, .quietDanger:
            shape.strokeBorder(hovering && enabled ? P.fieldBorder : .clear, lineWidth: 1)
        case .dashed:
            shape.strokeBorder(hovering ? P.ink3 : P.fieldBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}

struct IconButtonStyle: ButtonStyle {
    var danger = false
    var size: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, danger: danger, size: size)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let danger: Bool
    let size: CGFloat
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .frame(width: size, height: size)
            .foregroundStyle(danger ? P.error : P.ink)
            .box()
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.45)
            .focusRing()
    }
}

/// Underlined text button, for secondary actions that sit inside prose.
struct LinkButton: View {
    let title: String
    var size: CGFloat = T.type.small
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(T.font(size))
                .underline(true, color: hovering ? P.ink : P.ink2)
                .foregroundStyle(hovering ? P.ink : P.ink2)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .focusRing()
    }
}

// MARK: - Small parts

struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(T.font(T.type.label, .medium))
            .tracking(T.faces.labelTracking)
            .foregroundStyle(P.ink3)
            .lineLimit(1)
    }
}

struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(T.font(T.type.caption, .semibold))
            .tracking(0.4)
            .foregroundStyle(P.ink2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .dashedBorder(P.ink3, radius: T.radii.chip)
            .fixedSize()
    }
}

struct SwitchPill: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isOn {
                    Text("On").font(T.font(T.type.small, .bold)).foregroundStyle(P.ink).frame(width: 22)
                    Circle().fill(P.ink).frame(width: 20, height: 20)
                } else {
                    Circle().fill(P.knobOff).frame(width: 20, height: 20)
                    Text("Off").font(T.font(T.type.small, .bold)).foregroundStyle(P.ink).frame(width: 22)
                }
            }
            .padding(.leading, isOn ? 8 : 4)
            .padding(.trailing, isOn ? 4 : 8)
            .frame(height: 28)
            .background(Capsule().fill(P.field))
            .overlay(Capsule().strokeBorder(P.fieldBorder, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
        .focusRing(radius: 14)
    }
}

/// A plain text field, or its text when rendering offscreen.
struct InkTextField: View {
    @Binding var text: String
    var font: Font
    var alignment: TextAlignment = .leading
    var placeholder = ""
    var focus: FocusState<Bool>.Binding
    @Environment(\.staticRender) private var staticRender

    var body: some View {
        if staticRender {
            Text(text.isEmpty ? placeholder : text)
                .font(font)
                .foregroundStyle(text.isEmpty ? P.ink3 : P.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(P.ink)
                .multilineTextAlignment(alignment)
                .focused(focus)
        }
    }
}

// MARK: - Icons

enum IconKind { case splitV, splitH, delete, reset, warn, chevron, check, plus, dots, cursor, tray }

/// The mock's inline SVG icons, drawn as paths on their own view boxes.
struct Icon: View {
    let kind: IconKind
    var size: CGFloat = 16

    var body: some View {
        Canvas { context, canvas in
            let box: CGFloat = kind == .warn || kind == .check || kind == .plus ? 12 : kind == .chevron ? 10 : 16
            let s = canvas.width / box
            context.scaleBy(x: s, y: s)
            let line = StrokeStyle(lineWidth: kind == .plus || kind == .chevron ? 1.6 : kind == .check ? 1.8 : 1.4)
            let ink = GraphicsContext.Shading.foreground
            switch kind {
            case .splitV:
                context.stroke(Path(roundedRect: CGRect(x: 1.5, y: 2.5, width: 13, height: 11), cornerRadius: 1), with: ink, style: line)
                context.stroke(Path { $0.move(to: CGPoint(x: 8, y: 2.5)); $0.addLine(to: CGPoint(x: 8, y: 13.5)) }, with: ink, style: line)
            case .splitH:
                context.stroke(Path(roundedRect: CGRect(x: 1.5, y: 2.5, width: 13, height: 11), cornerRadius: 1), with: ink, style: line)
                context.stroke(Path { $0.move(to: CGPoint(x: 1.5, y: 8)); $0.addLine(to: CGPoint(x: 14.5, y: 8)) }, with: ink, style: line)
            case .delete:
                context.stroke(Path {
                    $0.move(to: CGPoint(x: 3, y: 4.5)); $0.addLine(to: CGPoint(x: 13, y: 4.5))
                    $0.move(to: CGPoint(x: 6.5, y: 4.5)); $0.addLine(to: CGPoint(x: 6.5, y: 3))
                    $0.addLine(to: CGPoint(x: 9.5, y: 3)); $0.addLine(to: CGPoint(x: 9.5, y: 4.5))
                    $0.move(to: CGPoint(x: 4.5, y: 4.5)); $0.addLine(to: CGPoint(x: 5.1, y: 13.5))
                    $0.addLine(to: CGPoint(x: 10.9, y: 13.5)); $0.addLine(to: CGPoint(x: 11.5, y: 4.5))
                }, with: ink, style: line)
            case .reset:
                context.stroke(Path(roundedRect: CGRect(x: 2.5, y: 3.5, width: 11, height: 9), cornerRadius: 1), with: ink, style: line)
            case .warn:
                context.stroke(Path {
                    $0.move(to: CGPoint(x: 6, y: 1)); $0.addLine(to: CGPoint(x: 11, y: 10))
                    $0.addLine(to: CGPoint(x: 1, y: 10)); $0.closeSubpath()
                    $0.move(to: CGPoint(x: 6, y: 4.5)); $0.addLine(to: CGPoint(x: 6, y: 7))
                    $0.move(to: CGPoint(x: 6, y: 8.2)); $0.addLine(to: CGPoint(x: 6, y: 9))
                }, with: ink, style: line)
            case .chevron:
                context.stroke(Path {
                    $0.move(to: CGPoint(x: 1, y: 3)); $0.addLine(to: CGPoint(x: 5, y: 7)); $0.addLine(to: CGPoint(x: 9, y: 3))
                }, with: ink, style: line)
            case .check:
                context.stroke(Path {
                    $0.move(to: CGPoint(x: 2, y: 6.5)); $0.addLine(to: CGPoint(x: 4.5, y: 9)); $0.addLine(to: CGPoint(x: 10, y: 3))
                }, with: ink, style: line)
            case .plus:
                context.stroke(Path {
                    $0.move(to: CGPoint(x: 6, y: 1)); $0.addLine(to: CGPoint(x: 6, y: 11))
                    $0.move(to: CGPoint(x: 1, y: 6)); $0.addLine(to: CGPoint(x: 11, y: 6))
                }, with: ink, style: line)
            case .dots:
                for x in [3.0, 8.0, 13.0] {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: 6.5, width: 3, height: 3)), with: ink)
                }
            case .cursor:
                let arrow = Path {
                    $0.move(to: CGPoint(x: 1, y: 1)); $0.addLine(to: CGPoint(x: 1, y: 13))
                    $0.addLine(to: CGPoint(x: 4.2, y: 9.8)); $0.addLine(to: CGPoint(x: 6.6, y: 15.4))
                    $0.addLine(to: CGPoint(x: 9, y: 14.6)); $0.addLine(to: CGPoint(x: 6.6, y: 9))
                    $0.addLine(to: CGPoint(x: 11.4, y: 9)); $0.closeSubpath()
                }
                context.fill(arrow, with: .color(.white))
                context.stroke(arrow, with: .color(.black), lineWidth: 1)
            case .tray:
                context.stroke(Path {
                    $0.move(to: CGPoint(x: 2, y: 7)); $0.addLine(to: CGPoint(x: 14, y: 7))
                    $0.move(to: CGPoint(x: 2, y: 7)); $0.addLine(to: CGPoint(x: 3, y: 13)); $0.addLine(to: CGPoint(x: 13, y: 13)); $0.addLine(to: CGPoint(x: 14, y: 7))
                    $0.move(to: CGPoint(x: 6, y: 7)); $0.addLine(to: CGPoint(x: 6.5, y: 9)); $0.addLine(to: CGPoint(x: 9.5, y: 9)); $0.addLine(to: CGPoint(x: 10, y: 7))
                }, with: ink, style: line)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A layout preset drawn on a 24 × 15 frame, as in the mock's preset row.
struct PresetGlyph: View {
    let zones: [(x: Double, y: Double, w: Double, h: Double)]

    var body: some View {
        Canvas { context, _ in
            let ink = GraphicsContext.Shading.foreground
            context.stroke(Path(roundedRect: CGRect(x: 0.5, y: 0.5, width: 23, height: 14), cornerRadius: 1), with: ink, lineWidth: 1)
            for zone in zones {
                context.fill(Path(CGRect(x: 2 + zone.x * 0.2, y: 2 + zone.y * 0.11,
                                         width: max(1, zone.w * 0.2 - 1), height: max(1, zone.h * 0.11 - 1))), with: ink)
            }
        }
        .frame(width: 24, height: 15)
    }
}

// MARK: - Layout

/// Left-to-right rows that wrap, for chips.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].items.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].items.isEmpty ? 0 : spacing
            rows[rows.count - 1].items.append(index)
            rows[rows.count - 1].width += size.width + gap
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.items.isEmpty }
    }
}
