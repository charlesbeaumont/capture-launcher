import AppKit
import SwiftUI

/// ONE panel for the app's lifetime — never recreated per show, never
/// close()d. The v0.2–v0.3 per-toggle panel churn (a fresh WindowServer
/// window seizing key on every hotkey press) is the prime suspect for a
/// system-wide hover/tooltip failure in *other* focused apps after days of
/// uptime. Per-show freshness comes from `setContent(_:)` instead.
final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static let width: CGFloat = 720
    static let seedHeight: CGFloat = 88

    private let container: NSView
    private var host: NSView?

    init() {
        container = NSView(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.seedHeight))
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.seedHeight),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Belt and braces: even an accidental close() must not dealloc the
        // panel (NSPanel defaults this to true).
        isReleasedWhenClosed = false
        // becomesKeyOnlyIfNeeded must stay OFF (default false). With it set,
        // key-window return to the previous app after orderOut becomes FLAKY
        // (verified 2026-07-15: failed on the 3rd of 3 toggle cycles) — hover
        // dies in the focused app behind us. See CLAUDE.md hard constraints.

        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        // Matches Theme.cornerRadius — the mask stays mandatory: it clips the
        // hosting view's rectangular corners so windowBackgroundColor never
        // leaks around the themed background.
        container.layer?.cornerRadius = Theme.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        contentView = container
    }

    /// Installs a fresh SwiftUI tree for this show. A NEW NSHostingView each
    /// time is deliberate: replacing `rootView` on a kept hosting view would
    /// preserve SwiftUI structural identity, so `.onAppear` focus setup and
    /// `@FocusState` would NOT reset. A fresh hosting view reproduces the old
    /// fresh-panel semantics with zero WindowServer involvement.
    func setContent<Content: View>(_ rootView: Content) {
        host?.removeFromSuperview()
        let newHost = NSHostingView(rootView: rootView)
        newHost.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(newHost)
        NSLayoutConstraint.activate([
            newHost.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            newHost.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            newHost.topAnchor.constraint(equalTo: container.topAnchor),
            newHost.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        host = newHost
    }

    func resize(toHeight height: CGFloat) {
        let clamped = max(60, min(height, 600))
        guard abs(frame.height - clamped) > 0.5 else { return }
        var f = frame
        f.origin.y = f.maxY - clamped
        f.size.height = clamped
        setFrame(f, display: true, animate: false)
        invalidateShadow()
    }
}
