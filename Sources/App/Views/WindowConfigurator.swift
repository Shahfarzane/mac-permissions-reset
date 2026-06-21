import SwiftUI
import AppKit

/// A behind-window blur backdrop (the translucent "desktop shows through" look).
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// Configures the system-created `WindowGroup` window for the translucent,
/// title-less Loop look — WITHOUT breaking mouse clicks.
///
/// Key decision: we keep `.fullSizeContentView` (so the behind-window blur fills
/// the whole window, traffic lights included) but the SwiftUI content does NOT
/// `.ignoresSafeArea()`. That leaves a thin title-bar safe area at the top owned
/// by AppKit (where the traffic lights live and where window dragging happens),
/// and places every interactive control just below it — so real mouse clicks
/// reach the buttons instead of being swallowed by the title-bar drag layer.
/// (Reparenting the traffic lights / isa-swizzling the hosting view's safe area —
/// Loop/Luminare's approach — either regressed light mode or crashed
/// `NSHostingView`'s dynamic-property machinery, so we avoid both.)
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        for delay in [0.0, 0.05, 0.2, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { Self.configure(view.window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(nsView.window) }
    }

    private static func configure(_ window: NSWindow?) {
        guard let window else { return }
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        // Traffic lights stay at AppKit's default top-left position (visible in
        // both light and dark, managed entirely by AppKit) within the thin
        // title-bar strip above the content.
    }
}
