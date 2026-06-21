import SwiftUI
import Foundation
import AppResetKit

struct AppDetailView: View {
    let app: AppInfo
    @Bindable var model: AppDetailModel
    let fullDiskAccess: Bool
    /// Height of the title-bar strip (measured at the root), so the identity can
    /// hug the bottom of the strip in line with the action buttons below it.
    var stripHeight: CGFloat = 0

    @Environment(IconProvider.self) private var icons
    @State private var pending: PendingReset?

    var body: some View {
        // Custom top region (replaces the system toolbar): app identity + actions,
        // then the pinned Overview as a fixed header, then the scrolling sections.
        // The window's title bar is hidden, so this top bar IS the visible top.
        VStack(spacing: 0) {
            detailTopBar
            Divider()

            if let report = model.report {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.sectionSpacing) {
                        OverviewSection(report: report)
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
                    .padding(.horizontal, DS.contentPadding)
                    .padding(.top, DS.topBarContentGap)
                    .padding(.bottom, DS.sectionSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.top)
                .scrollEdgeEffectStyle(.hard, for: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Inspecting \(app.name)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: app.id) { await model.load(app) }
        .confirmationDialog(
            pending.map { "Reset \($0.label) for \(app.name)?" } ?? "",
            isPresented: presentingBinding,
            titleVisibility: .visible,
            presenting: pending
        ) { item in
            Button("Move to Trash") {
                Task { await model.reset(app, categories: item.categories, permanent: false) }
            }
            Button("Delete Permanently", role: .destructive) {
                Task { await model.reset(app, categories: item.categories, permanent: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(confirmationMessage(for: item))
        }
        .overlay { stripIdentity }
        .overlay(alignment: .bottom) { statusOverlay }
        .animation(.easeInOut(duration: 0.2), value: model.statusMessage)
        .animation(.easeInOut(duration: 0.2), value: model.isResetting)
    }

    private var presentingBinding: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    /// App identity (icon + name) lifted UP into the title-bar strip — matching
    /// the sidebar's "Apps" title — so both panes start at the same height. It's
    /// an image + text with hit-testing disabled, so sitting in the (draggable)
    /// title-bar region is safe. The bundle id lives in the Overview section.
    private var stripIdentity: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: icons.icon(forPath: app.path))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(app.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)
            .padding(.bottom, 4)
            .frame(height: stripHeight, alignment: .bottom)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Reset actions, hugging just BELOW the title-bar strip (so they stay
    /// clickable) and right-aligned — landing on the same line as the identity.
    private var detailTopBar: some View {
        HStack(spacing: 8) {
            Spacer()
            detailActions
        }
        .frame(height: DS.controlHeight + 4, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    private var detailActions: some View {
        HStack(spacing: 8) {
            // Appears only after something was moved to the Trash this session.
            if !model.trashedItems.isEmpty {
                Button {
                    Task { await model.restore(app) }
                } label: {
                    Label("Restore (\(model.trashedItems.count))", systemImage: "arrow.uturn.backward")
                }
                .loopButton(.plain)
                .help("Move the \(model.trashedItems.count) trashed item\(model.trashedItems.count == 1 ? "" : "s") back from the Trash")
                .disabled(model.isResetting)
            }

            Button {
                Task { await model.rescan(app) }
            } label: {
                if model.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .loopIconButton(.plain)
            .help("Re-scan this app")
            .disabled(model.isResetting || model.isLoading)

            Button(role: .destructive) {
                pending = PendingReset(categories: ResetCategory.defaultSweep, label: "everything")
            } label: {
                Label("Full Reset…", systemImage: "arrow.counterclockwise")
            }
            .loopButton(.destructive)
            .disabled(model.report == nil || model.isResetting)
        }
        .animation(.easeInOut(duration: 0.2), value: model.trashedItems.isEmpty)
    }

    private func confirmationMessage(for item: PendingReset) -> String {
        if item.categories == [.tcc] {
            return "This resets privacy permissions so \(app.name) asks for them again next launch."
        }
        return "Move the selected data to the Trash — you can restore it here — or delete it permanently. Privacy resets make the app re-prompt; macOS cannot grant another app's permissions for you."
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
