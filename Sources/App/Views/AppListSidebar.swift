import SwiftUI
import AppKit
import AppResetKit

struct AppListSidebar: View {
    @Bindable var model: AppListModel
    @Binding var selection: AppInfo.ID?
    @AppStorage("appearanceMode") private var appearance: AppearanceMode = .system

    var body: some View {
        VStack(spacing: 0) {
            topBar
            List(selection: $selection) {
            if model.showsDeveloperSection {
                Section {
                    if model.developerApps.isEmpty {
                        Text(model.search.isEmpty ? "No installed apps found." : "No matches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.developerApps) { app in
                            AppRow(app: app).tag(app.id)
                        }
                    }
                } header: {
                    sectionHeader("Installed Apps", "shippingbox")
                }
            }

            if model.showsSystemSection {
                Section {
                    if model.systemApps.isEmpty {
                        Text(model.search.isEmpty ? "No system apps found." : "No matches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.systemApps) { app in
                            AppRow(app: app).tag(app.id)
                        }
                    }
                } header: {
                    sectionHeader("System Apps", "apple.logo")
                }
            }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 38)
            .overlay {
                if model.isLoading && model.apps.isEmpty {
                    ProgressView("Loading apps…")
                } else if model.developerApps.isEmpty && model.systemApps.isEmpty && !model.search.isEmpty {
                    ContentUnavailableView.search(text: model.search)
                }
            }

            appearanceFooter
        }
        .background(VisualEffectView(material: .sidebar))
    }

    /// App-level appearance control, pinned at the bottom of the sidebar.
    private var appearanceFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Text("Appearance")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Image(systemName: mode.systemImage)
                            .help(mode.label)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    /// Custom top bar drawn in the strip reserved for the relocated traffic
    /// lights — replaces the system toolbar so nothing floats over the list.
    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Apps")
                    .font(.title3.weight(.semibold))
                Spacer()
                filterMenu
            }
            .frame(height: WindowConfigurator.topBarHeight)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps", text: $model.search)
                    .textFieldStyle(.plain)
                if !model.search.isEmpty {
                    Button { model.search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))

            if !model.hasFullDiskAccess {
                FullDiskAccessBanner()
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var filterMenu: some View {
        Menu {
            // Explicit buttons (not an inline Picker) so a mouse pick always
            // commits the selection; a checkmark shows the active filter.
            ForEach(AppFilter.allCases) { option in
                Button {
                    model.filter = option
                } label: {
                    Label(option.label, systemImage: model.filter == option ? "checkmark" : option.systemImage)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title3)
        }
        .menuStyle(.button)
        .loopButton(.plain, size: .compact)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter apps — currently \(model.filter.label)")
    }

    private func sectionHeader(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .textCase(nil)
    }
}

private struct AppRow: View {
    let app: AppInfo
    @Environment(IconProvider.self) private var icons

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icons.icon(forPath: app.path))
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 3)
    }
}
