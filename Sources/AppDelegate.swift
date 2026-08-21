import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: LauncherPanel?
    /// Block-based observers do not auto-deregister; hold the token so deinit
    /// can balance the addObserver in `ensurePanel`.
    private var resignKeyObserver: NSObjectProtocol?

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
        // Activate BEFORE ordering front. Taking key without activating leaves
        // the previously-focused app active but with no key window anywhere in
        // its process — and hover, tooltips and cursor rects all hang off
        // .activeInKeyWindow tracking areas, so all three die at once until our
        // panel is destroyed. That is the multi-day hover bug. Under .accessory
        // there is no Dock icon and no menu bar, so activating is invisible.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        guard let panel, panel.isVisible else { return } // double-hide benign
        // Hide is EXACTLY orderOut — nothing else. This is the Spotlight /
        // Alfred / Raycast model: activate on show, orderOut on hide, and let
        // AppKit's own app-switching machinery return the previous app.
        //
        // Nothing hands focus back by force. showPanel activates us properly,
        // so orderOut is a normal deactivation and AppKit restores the previous
        // app as both active and key on its own.
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
        // Installed here, not in showPanel, so it can never accumulate one
        // observer per show. Scoped to `created` so the Settings window's own
        // resign-key does not dismiss the panel.
        //
        // Safe now that showPanel activates: a resign-key on a non-activating
        // panel in an INACTIVE app fires for OS-internal reasons and used to
        // make the panel vanish ~1s after showing. Once we are genuinely the
        // active app, resign-key means a real focus loss.
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: created,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hidePanel() }
        }
        return created
    }

    isolated deinit {
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
        }
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
