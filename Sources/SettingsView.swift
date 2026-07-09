import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    let appDelegate: AppDelegate

    @AppStorage(Theme.storageKey) private var themeName = Theme.solarizedLight.name
    @AppStorage(DailyCapture.templateKey) private var uriTemplate = DailyCapture.defaultTemplate
    @AppStorage(BearCLI.pathKey) private var bearcliPath = BearCLI.defaultPath
    @AppStorage(DestinationStore.inboxNoteIdKey) private var inboxNoteId = DestinationStore.defaultInboxNoteId
    @AppStorage(DestinationStore.registryTitleKey) private var registryTitle = DestinationStore.defaultRegistryTitle
    @AppStorage(FilingAgent.enabledKey) private var filingAgentEnabled = true
    @AppStorage(FilingAgent.tidyKey) private var filingAgentTidy = true
    @AppStorage(FilingAgent.pathKey) private var claudePath = ""
    @AppStorage(FilingAgent.modelKey) private var filingAgentModel = ""

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $themeName) {
                    ForEach(Theme.all) { theme in
                        Text(theme.name).tag(theme.name)
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
                        if let refreshed = appDelegate.store.lastRefresh {
                            Text("refreshed \(refreshed.formatted(date: .omitted, time: .standard))")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("not refreshed yet — showing cache")
                                .foregroundStyle(.orange)
                        }
                        if !appDelegate.store.registryFound {
                            Text("no “\(registryTitle)” note found — using tag scan only")
                                .foregroundStyle(.orange)
                        }
                        if let error = appDelegate.store.lastError {
                            Text(error)
                                .foregroundStyle(.red)
                                .lineLimit(3)
                        }
                    }
                    .font(.caption)
                }
                Button("Refresh now") { appDelegate.refreshDestinations() }
                TextField("Registry note title", text: $registryTitle)
                Text("A Bear note listing active destinations, one `- project/x` line each; `!paused` hides a line from the default list; `general-reference: <note-id>` names the triage default target. Maintained by your second-brain skills.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Filing") {
                TextField("bearcli path", text: $bearcliPath)
                    .font(.system(.caption, design: .monospaced))
                TextField("Inbox note id", text: $inboxNoteId)
                    .font(.system(.caption, design: .monospaced))
                Toggle("Refine placement with Claude", isOn: $filingAgentEnabled)
                Toggle("Tidy spelling & grammar", isOn: $filingAgentTidy)
                    .disabled(!filingAgentEnabled)
                Text("After a capture lands in a note's ## Captured section, a short-lived `claude -p` run moves it to the right spot per the note's own conventions — and, if tidying is on, fixes obvious spelling/grammar without rephrasing or translating. Log: ~/Library/Logs/Capture/filing.log")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("claude path (default ~/.local/bin/claude)", text: $claudePath)
                    .font(.system(.caption, design: .monospaced))
                TextField("Model override (empty = CLI default)", text: $filingAgentModel)
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
