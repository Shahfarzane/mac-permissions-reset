import SwiftUI

/// User-selectable app appearance. Persisted via `@AppStorage`.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// `nil` follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Shared design tokens so the sidebar and detail speak one visual language —
/// translucent surfaces, grouped rounded sections, hairline separators, and
/// consistent corner radii / spacing / typography. Inspired by Loop (Luminare).
enum DS {
    /// Grouped sections / cards in the detail pane.
    static let cardCornerRadius: CGFloat = 12
    /// Inner controls, pills, fills.
    static let controlCornerRadius: CGFloat = 8
    /// Vertical gap BETWEEN detail sections.
    static let sectionSpacing: CGFloat = 16
    /// Gap between a section's header label and its card (Luminare-tight).
    static let headerSpacing: CGFloat = 4
    /// Inner padding of a section card.
    static let cardPadding: CGFloat = 12
    /// Padding around the scrolling detail content.
    static let contentPadding: CGFloat = 12
    /// Per-row vertical padding inside a section.
    static let rowPadding: CGFloat = 6
}

extension View {
    /// A grouped, rounded, material surface used for every card/section so they
    /// read as one family. Borderless like Loop — the material fill alone
    /// separates it from the translucent window background.
    func cardSurface(cornerRadius: CGFloat = DS.cardCornerRadius) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
    }

}

extension Text {
    /// Small, secondary, medium-weight label used above grouped content — the
    /// Loop section-header treatment.
    func sectionHeaderStyle() -> some View {
        font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
    }
}

// MARK: - Loop-style button family
//
// One button style for the whole app, ported from Loop's Luminare button:
// a flat translucent "plateau" pill (12pt corner radius, fixed height, hairline
// border, medium weight). Only the fill changes between variants — Loop never
// uses a solid saturated button. Hover/press deepen the fill (0.2/0.3/0.4 ramp).

enum LoopButtonRole { case plain, prominent, destructive }

/// `.regular` fills its container (section-wide actions); `.compact` hugs its
/// label (per-row resets, header actions, top-bar icon buttons).
enum LoopButtonSize { case regular, compact }

struct LoopButtonStyle: ButtonStyle {
    var role: LoopButtonRole = .plain
    var size: LoopButtonSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, role: role, size: size)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        let role: LoopButtonRole
        let size: LoopButtonSize
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        private var cornerRadius: CGFloat { DS.cardCornerRadius }
        private var minHeight: CGFloat { size == .regular ? 32 : 24 }

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .font(.callout.weight(.medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, size == .regular ? 12 : 9)
                .frame(maxWidth: size == .regular ? .infinity : nil, minHeight: minHeight)
                .background(fill(pressed: pressed), in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.12), value: pressed)
        }

        private func fill(pressed: Bool) -> AnyShapeStyle {
            let level: Double = pressed ? 0.4 : (isHovering ? 0.3 : 0.2)
            switch role {
            case .prominent:
                return AnyShapeStyle(Color.accentColor.opacity(level))
            case .destructive:
                return AnyShapeStyle(Color.red.opacity(level))
            case .plain:
                let active = pressed || isHovering
                if colorScheme == .dark {
                    return AnyShapeStyle(active ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
                } else {
                    return AnyShapeStyle(active ? AnyShapeStyle(.quinary) : AnyShapeStyle(Color.white.opacity(0.7)))
                }
            }
        }

        private var foreground: Color {
            switch role {
            case .plain: .primary
            case .prominent: .accentColor
            case .destructive: .red
            }
        }
    }
}

extension View {
    /// Apply the one Loop button family. Use instead of `.bordered` / `.glass`.
    func loopButton(_ role: LoopButtonRole = .plain, size: LoopButtonSize = .regular) -> some View {
        buttonStyle(LoopButtonStyle(role: role, size: size)).focusable(false)
    }

    /// Back-compat shim: old per-row/header reset buttons were small + red.
    func resetButtonStyle() -> some View {
        loopButton(.destructive, size: .compact)
    }
}
