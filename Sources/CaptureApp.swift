import SwiftUI

@main
struct CaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Capture", systemImage: "brain.fill") {
            Button("Open Capture") { appDelegate.showPanel() }
                .keyboardShortcut("o")
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
            SettingsView()
        }
    }
}
