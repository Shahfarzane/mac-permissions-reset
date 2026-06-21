import SwiftUI

/// A titled content card used throughout the detail pane. Solid material keeps
/// dense permission/data tables legible; Liquid Glass is reserved for floating
/// accents (banner, primary actions).
struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    var subtitle: String?
    var headerAccessory: AnyView?
    @ViewBuilder var content: () -> Content

    init(
        _ title: String,
        systemImage: String,
        subtitle: String? = nil,
        headerAccessory: AnyView? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.headerAccessory = headerAccessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.headerSpacing) {
            // Loop/Luminare-style: the section label lives ABOVE the card as a
            // small, secondary caption (LuminareSection header treatment), so the
            // card reads as a clean group of rows and top/bottom rhythm stays even.
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                Spacer()
                headerAccessory
            }
            .padding(.horizontal, DS.cardCornerRadius / 2)

            content()
                .padding(DS.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
        }
    }
}
