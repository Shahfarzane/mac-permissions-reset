import SwiftUI
import AppKit

/// Caches app icons fetched from the workspace so list scrolling and redraws
/// don't re-hit the filesystem.
@MainActor
@Observable
final class IconProvider {
    private var cache: [String: NSImage] = [:]

    func icon(forPath path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}
