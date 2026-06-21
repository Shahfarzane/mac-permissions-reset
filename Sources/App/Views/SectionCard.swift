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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                headerAccessory
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }
}
