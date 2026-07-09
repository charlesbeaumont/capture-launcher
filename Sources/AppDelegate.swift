import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: LauncherPanel?
    /// Whoever had focus before the panel took key — restored on hide.
    private var previousApp: NSRunningApplication?

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
        if !panel.isVisible {
            // Snapshot who has focus BEFORE we take key from them.
            previousApp = NSWorkspace.shared.frontmostApplication
        }
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
        panel.makeFirstResponder(nil) // end the field-editor session before reuse
        panel.orderOut(nil)
        handBackFocus()
    }

    /// Deterministically re-assert the previous app's key window. Bare
    /// orderOut leaves key-window return to WindowServer heuristics — the
    /// state suspected to decay over days (the 2026-07-08 hover bug).
    private func handBackFocus() {
        defer { previousApp = nil }
        guard let previous = previousApp,
              !previous.isTerminated,
              previous.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              // The panel persists on focus loss: if the user switched apps
              // while it was open, do NOT yank them back to the old app.
              NSWorkspace.shared.frontmostApplication?.processIdentifier
                  == previous.processIdentifier
        else { return }
        if !previous.activate(from: .current, options: []) {
            NSLog("focus hand-back denied for %@", previous.bundleIdentifier ?? "?")
        }
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
