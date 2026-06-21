import SwiftUI
import AppKit
import AppResetKit

struct AppListSidebar: View {
    @Bindable var model: AppListModel
    @Binding var selection: AppInfo.ID?

    var body: some View {
        List(selection: $selection) {
            Section {
                if model.developerApps.isEmpty {
                    Text(model.search.isEmpty ? "No developer apps found." : "No matches")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.developerApps) { app in
                        AppRow(app: app).tag(app.id)
                    }
                }
            } header: {
                Label("Developer Apps", systemImage: "hammer")
            }

            if model.systemGroupVisible {
                Section {
                    ForEach(model.systemApps) { app in
                        AppRow(app: app).tag(app.id)
                    }
                } header: {
                    Label("System Apps", systemImage: "apple.logo")
                }
            }
        }
        .overlay {
            if model.isLoading && model.apps.isEmpty {
                ProgressView("Loading apps…")
            } else if model.developerApps.isEmpty && model.systemApps.isEmpty && !model.search.isEmpty {
                ContentUnavailableView.search(text: model.search)
            }
        }
        .searchable(text: $model.search, placement: .sidebar, prompt: "Search apps")
        .safeAreaInset(edge: .top, spacing: 0) {
            if !model.hasFullDiskAccess {
                FullDiskAccessBanner()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
        }
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $model.showSystem) {
                    Label("System Apps", systemImage: "apple.logo")
                }
                .toggleStyle(.button)
                .help("Show Apple / system apps")
            }
        }
        .navigationTitle("Apps")
    }
}

private struct AppRow: View {
    let app: AppInfo
    @Environment(IconProvider.self) private var icons

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icons.icon(forPath: app.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }
}
