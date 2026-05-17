import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: LauncherPanel?

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { configure() }
    }

    private func configure() {
        NSApp.setActivationPolicy(.accessory)

        KeyboardShortcuts.onKeyUp(for: .toggleLauncher) { [weak self] in
            self?.togglePanel()
        }
    }

    func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private static let fadeDuration: TimeInterval = 0.1

    func showPanel() {
        let panel = makeFreshPanel()
        positionPanel(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 1
        }
    }

    func hidePanel() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        })
    }

    private func makeFreshPanel() -> LauncherPanel {
        panel?.orderOut(nil)
        let view = LauncherView(
            onSubmit: { [weak self] text in
                DailyCapture.send(text)
                self?.hidePanel()
            },
            onCancel: { [weak self] in
                self?.hidePanel()
            },
            onHeightChange: { [weak self] height in
                self?.panel?.resize(toHeight: height)
            }
        )
        let panel = LauncherPanel(rootView: view)
        self.panel = panel
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - (visible.height * 0.28) - size.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
