import SwiftUI
import AppResetKit
import PermissionFlowExtendedStatus

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
                .background(WindowConfigurator())
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh Apps") { Task { await listModel.load() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

/// Sidebar + detail master/detail layout.
///
/// A custom split (not `NavigationSplitView`) so we fully control the top region:
/// the window's title bar is hidden/transparent and the traffic lights are
/// relocated into the content, so each column draws its own top bar. This is the
/// Loop / Luminare approach — `NavigationSplitView` ignores the title-bar safe
/// area on macOS 26/27 and renders content under the toolbar.
struct RootView: View {
    @Bindable var listModel: AppListModel
    @Bindable var detailModel: AppDetailModel
    @State private var selection: AppInfo.ID?
    @AppStorage("appearanceMode") private var appearance: AppearanceMode = .system

    var body: some View {
        // Measure the title-bar strip height (the safe-area inset reserved for the
        // traffic lights) ONCE at the root, before the content consumes it, and
        // hand it to each column so they can lift their title to hug the content
        // and keep the empty band tight regardless of the OS's title-bar height.
        GeometryReader { proxy in
            let strip = proxy.safeAreaInsets.top
            HStack(spacing: 0) {
                AppListSidebar(model: listModel, selection: $selection, stripHeight: strip)
                    .frame(width: 300)

                // No Divider here — the sidebar draws its own full-height trailing
                // separator (in its safe-area-ignoring background layer) so the
                // line runs all the way up to the top of the window.
                detail(stripHeight: strip)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Content respects the title-bar safe area so the top bars sit below
            // the traffic-light strip and stay clickable; the blur backdrop
            // ignores the safe area so it fills the whole window (strip included).
            .background(VisualEffectView(material: .underWindowBackground).ignoresSafeArea())
            .preferredColorScheme(appearance.colorScheme)
        }
        .task {
            // Make the optional PermissionFlow status providers (bluetooth, media,
            // input monitoring, screen recording) available to the registry.
            PermissionFlowExtendedStatus.register()
            await listModel.load()
        }
    }

    @ViewBuilder
    private func detail(stripHeight: CGFloat) -> some View {
        if let app = listModel.app(for: selection) {
            AppDetailView(app: app, model: detailModel, fullDiskAccess: listModel.hasFullDiskAccess, stripHeight: stripHeight)
                .id(app.id)
        } else {
            ContentUnavailableView(
                "Select an App",
                systemImage: "app.badge.checkmark",
                description: Text("Choose an app to inspect what it declares, what it's been granted, and its data — then reset any of it.")
            )
        }
    }
}
