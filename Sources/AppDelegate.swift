import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: LauncherPanel?

    let bear = BearCLI()
    let store = DestinationStore()
    private(set) lazy var router = CaptureRouter(bear: bear, store: store)

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { configure() }
    }

    private func configure() {
        NSApp.setActivationPolicy(.accessory)

        store.loadCache()
        refreshDestinations()
        Task { [bear] in
            do {
                NSLog("bearcli version: %@", try await bear.version())
            } catch {
                NSLog("bearcli unavailable: %@", String(describing: error))
            }
        }

        KeyboardShortcuts.onKeyUp(for: .toggleLauncher) { [weak self] in
            self?.togglePanel(mode: .capture)
        }
        KeyboardShortcuts.onKeyUp(for: .triageInbox) { [weak self] in
            self?.togglePanel(mode: .triage)
        }

        // Dev affordance for scripts/dev.sh and headless UI checks.
        if CommandLine.arguments.contains("--show-on-launch") {
            showPanel(mode: .capture)
        } else if CommandLine.arguments.contains("--triage-on-launch") {
            showPanel(mode: .triage)
        }
    }

    func refreshDestinations() {
        store.refresh(using: bear)
    }

    func togglePanel(mode: LauncherModel.Mode) {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel(mode: mode)
        }
    }

    func showPanel(mode: LauncherModel.Mode) {
        refreshDestinations() // off the hot path; picker renders from memory
        let panel = ensurePanel()
        let model = LauncherModel(
            mode: mode,
            store: store,
            router: router,
            bear: bear,
            onFinish: { [weak self] in
                self?.hidePanel()
            }
        )
        panel.setContent(LauncherView(
            model: model,
            onHeightChange: { [weak self] height in
                self?.panel?.resize(toHeight: height)
            }
        ))
        // Reset from the previous session's height (e.g. a triage session that
        // ended at route-stage height) — a fresh panel used to get this free.
        panel.resize(toHeight: LauncherPanel.seedHeight)
        positionPanel(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hidePanel() {
        guard let panel, panel.isVisible else { return } // double-hide benign
        // Hide is EXACTLY orderOut — nothing else. The panel is
        // .nonactivatingPanel and we only ever orderFrontRegardless() +
        // makeKey(), so our .accessory app never becomes the active app; the
        // previously-focused app stays active throughout and macOS returns its
        // key window natively on orderOut.
        //
        // The forced previous.activate() hand-back that used to live here was
        // removed 2026-07: it ran on every hide and was the only thing actively
        // reaching into another process's window state — the leading suspect
        // for the slow, multi-day system-wide hover/tooltip decay in OTHER apps.
        // It was insurance against an unproven "orderOut return decays over
        // days" theory; 0.2.0's plain-orderOut was clean per-cycle.
        //
        // Still FORBIDDEN in this path: makeFirstResponder(nil) before orderOut
        // (kills native key return, 100% reproducible) and
        // becomesKeyOnlyIfNeeded=true (makes key return flaky).
        panel.orderOut(nil)
    }

    /// The one panel for the app's lifetime — see LauncherPanel's doc comment
    /// for why it must never be recreated per show.
    private func ensurePanel() -> LauncherPanel {
        if let panel { return panel }
        let created = LauncherPanel()
        panel = created
        return created
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
