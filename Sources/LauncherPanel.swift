import AppKit
import SwiftUI

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static let width: CGFloat = 720

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 88),
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

        let host = NSHostingView(rootView: rootView)
        host.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 88))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.cornerRadius = 28
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        contentView = container
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
