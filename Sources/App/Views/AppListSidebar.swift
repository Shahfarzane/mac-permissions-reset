import SwiftUI
import AppKit
import AppResetKit

struct AppListSidebar: View {
    @Bindable var model: AppListModel
    @Binding var selection: AppInfo.ID?
    /// Height of the title-bar strip (measured at the root), so the title can
    /// hug the bottom of the strip right above the search field.
    var stripHeight: CGFloat = 0
    @AppStorage("appearanceMode") private var appearance: AppearanceMode = .system
    @State private var showingPermissions = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
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
            .contentMargins(.top, DS.topBarContentGap, for: .scrollContent)
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
        // The sidebar material — and its trailing separator — fill the whole
        // column height, up THROUGH the title-bar strip, so the traffic lights
        // float over the sidebar and the divider meets the top of the window
        // (Finder / Loop). The content above still respects the safe area, so the
        // controls stay clickable.
        .background(alignment: .trailing) {
            VisualEffectView(material: .sidebar)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 1)
                }
                .ignoresSafeArea()
        }
        // The title rides up in the strip beside the traffic lights.
        .overlay { stripTitle }
        .sheet(isPresented: $showingPermissions) { PermissionsView() }
    }

    /// App-level appearance control, pinned at the bottom of the sidebar.
    private var appearanceFooter: some View {
        VStack(spacing: 0) {
            Divider()
            permissionsRow
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

    /// Always-available entry to AppReset's own Permissions panel. Shows an
    /// orange dot when a required permission (Full Disk Access) is still missing.
    private var permissionsRow: some View {
        Button { showingPermissions = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                Text("Permissions")
                    .font(.callout)
                Spacer()
                if !model.hasFullDiskAccess {
                    Circle()
                        .fill(.orange)
                        .frame(width: 7, height: 7)
                        .help("Full Disk Access is not granted")
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    /// The "Apps" title, lifted UP into the title-bar strip beside the traffic
    /// lights so the top band isn't wasted. It's plain text with hit-testing
    /// disabled, so sitting in the (draggable) title-bar region is safe — it
    /// never steals clicks the way an interactive control would. The leading
    /// inset clears the traffic-light cluster.
    private var stripTitle: some View {
        VStack(spacing: 0) {
            Text("Apps")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, DS.trafficLightInset)
                .padding(.bottom, 4)
                .frame(height: stripHeight, alignment: .bottom)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Interactive top bar, sitting just BELOW the title-bar strip (so its
    /// controls stay clickable): the search field with the filter beside it.
    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                searchField
                filterMenu
            }

            if !model.hasFullDiskAccess {
                FullDiskAccessBanner(onManage: { showingPermissions = true })
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
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
        .frame(height: DS.controlHeight)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
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
        }
        .menuStyle(.button)
        .loopIconButton(.plain)
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
