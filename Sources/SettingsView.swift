import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    let appDelegate: AppDelegate

    @AppStorage(Theme.storageKey) private var themeName = Theme.ember.name
    @AppStorage(Theme.followSystemKey) private var followsSystem = false
    @AppStorage(Theme.lightThemeKey) private var lightThemeName = Theme.emberLight.name
    @AppStorage(Theme.darkThemeKey) private var darkThemeName = Theme.ember.name
    @AppStorage(DailyCapture.templateKey) private var uriTemplate = DailyCapture.defaultTemplate
    @AppStorage(BearCLI.pathKey) private var bearcliPath = BearCLI.defaultPath
    @AppStorage(DestinationStore.inboxNoteIdKey) private var inboxNoteId = DestinationStore.defaultInboxNoteId

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Match system light/dark", isOn: $followsSystem)
                if followsSystem {
                    Picker("Light theme", selection: $lightThemeName) {
                        ForEach(Theme.all) { theme in
                            Text(theme.name).tag(theme.name)
                        }
                    }
                    Picker("Dark theme", selection: $darkThemeName) {
                        ForEach(Theme.all) { theme in
                            Text(theme.name).tag(theme.name)
                        }
                    }
                } else {
                    Picker("Theme", selection: $themeName) {
                        ForEach(Theme.all) { theme in
                            Text(theme.name).tag(theme.name)
                        }
                    }
                }
            }

            Section("Hotkeys") {
                KeyboardShortcuts.Recorder("Capture", name: .toggleLauncher)
                KeyboardShortcuts.Recorder("Process inbox", name: .triageInbox)
            }

            Section("Destinations") {
                LabeledContent("Status") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(appDelegate.store.destinations.count) destinations")
                        if let refreshed = appDelegate.store.state(.bear).lastRefresh {
                            Text("refreshed \(refreshed.formatted(date: .omitted, time: .standard))")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("not refreshed yet — showing cache")
                                .foregroundStyle(.orange)
                        }
                        if let error = appDelegate.store.state(.bear).lastError {
                            Text(error)
                                .foregroundStyle(.red)
                                .lineLimit(3)
                        }
                    }
                    .font(.caption)
                }
                Button("Refresh now") { appDelegate.refreshDestinations() }
                Text("Every note tagged `#project`, `#personal`, `#person`, `#list` or `#agenda`, by title. Captures land verbatim as `- **date time**: text`: newest first under `## Captures` for projects and people, at the bottom for lists, under `## Topics` for agendas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Bear") {
                TextField("bearcli path", text: $bearcliPath)
                    .font(.system(.caption, design: .monospaced))
                TextField("Inbox note id", text: $inboxNoteId)
                    .font(.system(.caption, design: .monospaced))
            }

            Section("Fallback URI template") {
                Text("Used only when bearcli fails: the capture is parked in the Inbox via this Bear URL, with `{marker}` carrying the intended destination. Placeholders: {content} {time} {date} {datetime} {marker} — all URL-encoded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $uriTemplate)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 72)
                Button("Reset to Default") {
                    uriTemplate = DailyCapture.defaultTemplate
                }
            }

            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if let error = LaunchAtLogin.setEnabled(newValue) {
                            launchError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        } else {
                            launchError = nil
                        }
                    }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if LaunchAtLogin.requiresApproval {
                    Text("Open System Settings → General → Login Items to enable.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 640)
    }
}
