import SwiftUI
import AppResetKit

@main
struct AppResetApp: App {
    @State private var listModel = AppListModel()
    @State private var detailModel = AppDetailModel()
    @State private var icons = IconProvider()

    var body: some Scene {
        WindowGroup {
            RootView(listModel: listModel, detailModel: detailModel)
                .environment(icons)
                .frame(minWidth: 940, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh Apps") { Task { await listModel.load() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

/// Sidebar + detail master/detail layout.
struct RootView: View {
    @Bindable var listModel: AppListModel
    @Bindable var detailModel: AppDetailModel
    @State private var selection: AppInfo.ID?

    var body: some View {
        NavigationSplitView {
            AppListSidebar(model: listModel, selection: $selection)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            if let app = listModel.app(for: selection) {
                AppDetailView(app: app, model: detailModel, fullDiskAccess: listModel.hasFullDiskAccess)
                    .id(app.id)
            } else {
                ContentUnavailableView(
                    "Select an App",
                    systemImage: "app.badge.checkmark",
                    description: Text("Choose an app to inspect what it declares, what it's been granted, and its data — then reset any of it.")
                )
            }
        }
        .task { await listModel.load() }
    }
}
