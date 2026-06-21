import SwiftUI
import AppResetKit

struct DataStorageSection: View {
    let report: AppReport
    let isResetting: Bool
    /// (categories to reset, human label for the confirmation).
    let onReset: ([ResetCategory], String) -> Void

    private var grouped: [(category: DataCategory, locations: [DataLocation])] {
        let groups = Dictionary(grouping: report.dataLocations, by: \.category)
        return DataCategory.allCases.compactMap { category in
            guard let locations = groups[category], !locations.isEmpty else { return nil }
            return (category, locations)
        }
    }

    private var allDataCategories: [ResetCategory] {
        var seen = Set<ResetCategory>()
        var ordered: [ResetCategory] = []
        for group in grouped {
            let category = resetCategory(for: group.category)
            if seen.insert(category).inserted { ordered.append(category) }
        }
        return ordered
    }

    var body: some View {
        SectionCard(
            "Data & Storage",
            systemImage: "internaldrive",
            subtitle: formatBytes(report.totalDataSize),
            headerAccessory: report.dataLocations.isEmpty ? nil : AnyView(
                Button("Reset All Data") { onReset(allDataCategories, "all data") }
                    .resetButtonStyle()
                    .focusable(false)
                    .disabled(isResetting)
            )
        ) {
            if report.dataLocations.isEmpty {
                Text("No on-disk data found for this app.")
                    .foregroundStyle(.secondary)
                    .font(.body)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(grouped.enumerated()), id: \.element.category) { index, group in
                        if index > 0 { Divider() }
                        categoryGroup(group.category, group.locations)
                    }
                }
            }
        }
    }

    // A flat row group (no nested card) so the data locations read as part of
    // the section, not a detached container-in-a-container.
    private func categoryGroup(_ category: DataCategory, _ locations: [DataLocation]) -> some View {
        let total = locations.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(category.label)
                    .font(.body.weight(.medium))
                Text(formatBytes(total))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { onReset([resetCategory(for: category)], category.label) }
                    .resetButtonStyle()
                    .focusable(false)
                    .disabled(isResetting)
            }
            ForEach(locations) { location in
                Text(abbreviateHome(location.path))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, DS.rowPadding)
    }
}
