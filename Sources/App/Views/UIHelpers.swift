import SwiftUI
import AppResetKit

/// Color for a TCC authorization state.
func stateColor(_ state: TCCAuthState) -> Color {
    switch state {
    case .allowed: return .green
    case .denied: return .red
    case .limited: return .orange
    case .unknown, .notRequested: return .secondary
    }
}

/// Human-readable byte count for the GUI.
func formatBytes(_ count: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: count)
}

/// Replace the home prefix with `~` for compact paths.
func abbreviateHome(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

/// Which reset category clears a given on-disk data category.
func resetCategory(for category: DataCategory) -> ResetCategory {
    switch category {
    case .preferences, .preferencesByHost: return .defaults
    case .container: return .containers
    case .groupContainer: return .groupContainers
    case .caches: return .caches
    case .applicationSupport: return .appSupport
    case .savedState: return .savedState
    case .httpStorages: return .httpStorages
    case .webKit: return .webKit
    case .cookies: return .cookies
    case .logs: return .logs
    case .launchAgents: return .launchAgents
    }
}

/// The name `tccutil` expects for a service: the catalog uses the full
/// `kTCCServiceCamera` identifier, but `tccutil reset` wants the bare `Camera`.
func tccutilServiceName(_ identifier: String) -> String {
    let prefix = "kTCCService"
    return identifier.hasPrefix(prefix) ? String(identifier.dropFirst(prefix.count)) : identifier
}

/// Small rounded label used for permission sources and states.
struct Badge: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
