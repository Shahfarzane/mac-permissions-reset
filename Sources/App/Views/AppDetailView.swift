import SwiftUI
import Foundation
import AppResetKit

struct AppDetailView: View {
    let app: AppInfo
    @Bindable var model: AppDetailModel
    let fullDiskAccess: Bool

    @State private var permanent = false
    @State private var pending: PendingReset?

    var body: some View {
        Group {
            if let report = model.report {
                VStack(spacing: 0) {
                    // Overview is a fixed header (inside the content area, below
                    // the toolbar) so the app's identity is always visible no
                    // matter how the scrollable sections below are positioned.
                    OverviewSection(report: report)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            DeclaredPermissionsSection(report: report)
                            TCCSection(
                                report: report,
                                fullDiskAccess: fullDiskAccess,
                                isResetting: model.isResetting,
                                onResetService: { service in
                                    Task { await model.reset(app, categories: [.tcc], permanent: false, tccService: tccutilServiceName(service)) }
                                },
                                onResetAll: {
                                    Task { await model.reset(app, categories: [.tcc], permanent: false) }
                                }
                            )
                            DataStorageSection(
                                report: report,
                                isResetting: model.isResetting,
                                onReset: { categories, label in
                                    pending = PendingReset(categories: categories, label: label)
                                }
                            )
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .defaultScrollAnchor(.top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Inspecting \(app.name)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(app.name)
        .navigationSubtitle(app.bundleID)
        .toolbar { toolbarContent }
        .task(id: app.id) { await model.load(app) }
        .confirmationDialog(
            pending.map { "Reset \($0.label) for \(app.name)?" } ?? "",
            isPresented: presentingBinding,
            titleVisibility: .visible,
            presenting: pending
        ) { item in
            Button(permanent ? "Delete Permanently" : "Move to Trash", role: .destructive) {
                Task { await model.reset(app, categories: item.categories, permanent: permanent) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(confirmationMessage(for: item))
        }
        .overlay(alignment: .bottom) { statusOverlay }
        .animation(.easeInOut(duration: 0.2), value: model.statusMessage)
        .animation(.easeInOut(duration: 0.2), value: model.isResetting)
    }

    private var presentingBinding: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Toggle(isOn: $permanent) {
                Label("Delete Permanently", systemImage: permanent ? "trash.slash" : "trash")
            }
            .toggleStyle(.button)
            .help(permanent ? "Items will be permanently deleted" : "Items move to the Trash (recoverable)")

            Button {
                Task { await model.reload(app) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isResetting || model.isLoading)

            Button(role: .destructive) {
                pending = PendingReset(categories: ResetCategory.defaultSweep, label: "everything")
            } label: {
                Label("Full Reset…", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.glassProminent)
            .disabled(model.report == nil || model.isResetting)
        }
    }

    private func confirmationMessage(for item: PendingReset) -> String {
        let action = permanent ? "permanently delete" : "move to the Trash"
        if item.categories == [.tcc] {
            return "This resets privacy permissions so \(app.name) asks for them again next launch."
        }
        return "This will \(action) the selected data for \(app.name). Privacy resets make the app re-prompt; macOS cannot grant another app's permissions for you."
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if model.isResetting {
            Label("Resetting…", systemImage: "hourglass")
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(in: .capsule)
                .padding(.bottom, 16)
        } else if let message = model.statusMessage {
            Label(message, systemImage: model.statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(model.statusIsError ? Color.orange : Color.green)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(in: .capsule)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct PendingReset: Identifiable {
    let id = UUID()
    let categories: [ResetCategory]
    let label: String
}
