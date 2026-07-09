import SwiftUI

@main
struct CaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Capture", systemImage: "brain.fill") {
            Button("Open Capture") { appDelegate.showPanel(mode: .capture) }
                .keyboardShortcut("o")
            Button("Process Inbox") { appDelegate.showPanel(mode: .triage) }
                .keyboardShortcut("i")
            Button("Refresh Projects") { appDelegate.refreshDestinations() }
                .keyboardShortcut("r")
            Divider()
            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",")
            Divider()
            Button("Quit Capture") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(appDelegate: appDelegate)
        }
    }
}
