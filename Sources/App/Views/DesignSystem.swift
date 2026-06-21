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

    /// Height of the top bar each column draws below the traffic-light strip.
    /// Both columns reserve the same height so their headers align.
    static let topBarHeight: CGFloat = 44
    /// The ONE fixed gap between a column's top bar (the traffic-light region)
    /// and the content below it. Applied identically in the sidebar and the
    /// detail pane so the empty space at the top reads as a single, even band.
    static let topBarContentGap: CGFloat = 12
    /// The single height every button shares — text pills and square icon
    /// buttons alike — so the whole chrome reads as one control family.
    static let controlHeight: CGFloat = 28
    /// Leading inset that clears the macOS traffic-light cluster, so content
    /// lifted into the title-bar strip (e.g. the sidebar title) sits to its right.
    static let trafficLightInset: CGFloat = 78
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
// a flat translucent "plateau" pill (hairline border, medium weight) that ALWAYS
// stands `DS.controlHeight` tall — text pills and square icon buttons alike — so
// every button reads as one family. Only the fill changes between variants; Loop
// never uses a solid saturated button. Hover/press deepen the fill (0.2/0.3/0.4).

enum LoopButtonRole { case plain, prominent, destructive }

/// Width behaviour only — height is always `DS.controlHeight`. `.fill` stretches
/// to its container (section-wide actions); `.hug` wraps its label (per-row
/// resets, header and top-bar actions).
enum LoopButtonWidth { case hug, fill }

struct LoopButtonStyle: ButtonStyle {
    var role: LoopButtonRole = .plain
    var width: LoopButtonWidth = .hug
    /// Icon-only buttons render as a fixed square so every chrome icon matches.
    var iconOnly: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, role: role, width: width, iconOnly: iconOnly)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        let role: LoopButtonRole
        let width: LoopButtonWidth
        let iconOnly: Bool
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        private var cornerRadius: CGFloat { DS.cardCornerRadius }

        var body: some View {
            let pressed = configuration.isPressed
            let shape = RoundedRectangle(cornerRadius: cornerRadius)
            let label = configuration.label
                .font(iconOnly ? .system(size: 13, weight: .medium) : .callout.weight(.medium))
                .foregroundStyle(foreground)

            return sized(label)
                .background(fill(pressed: pressed), in: shape)
                .overlay(shape.strokeBorder(.quaternary, lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(shape)
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.12), value: pressed)
        }

        /// A fixed square for icon buttons; a fixed-height pill (optionally
        /// filling its container) for text buttons.
        @ViewBuilder
        private func sized(_ label: some View) -> some View {
            if iconOnly {
                label.frame(width: DS.controlHeight, height: DS.controlHeight)
            } else {
                label
                    .padding(.horizontal, 12)
                    .frame(maxWidth: width == .fill ? .infinity : nil, minHeight: DS.controlHeight, maxHeight: DS.controlHeight)
            }
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
    /// A text button in the one Loop family. Use instead of `.bordered` / `.glass`.
    func loopButton(_ role: LoopButtonRole = .plain, width: LoopButtonWidth = .hug) -> some View {
        buttonStyle(LoopButtonStyle(role: role, width: width)).focusable(false)
    }

    /// A square, icon-only button in the same family and at the same height as
    /// the text buttons — so the filter, refresh, and any other glyph buttons
    /// are visually identical.
    func loopIconButton(_ role: LoopButtonRole = .plain) -> some View {
        buttonStyle(LoopButtonStyle(role: role, iconOnly: true)).focusable(false)
    }

    /// The destructive reset action used by per-row and section-header buttons.
    func resetButtonStyle() -> some View {
        loopButton(.destructive)
    }
}
