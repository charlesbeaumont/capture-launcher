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

    @AppStorage(ProviderID.bear.enabledKey) private var bearEnabled = true
    @AppStorage(ProviderID.fifteenFive.enabledKey) private var fifteenFiveEnabled = false
    @AppStorage(FifteenFive.accountKey) private var fifteenFiveAccount = ""
    @State private var signingIn = false
    @State private var signInError: String?
    @State private var signIn = FifteenFiveSignIn()

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

            Section("Bear") {
                Toggle("Notes as destinations", isOn: $bearEnabled)
                    .onChange(of: bearEnabled) { appDelegate.refreshDestinations() }
                status(.bear)
                Button("Refresh now") { appDelegate.refreshDestinations() }
                Text("Every note tagged `#project`, `#personal`, `#person`, `#list` or `#agenda`, by title. Captures land verbatim as `- **date time**: text`: newest first under `## Captures` for projects and people, at the bottom for lists, under `## Topics` for agendas. The Inbox row always files here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("bearcli path", text: $bearcliPath)
                    .font(.system(.caption, design: .monospaced))
                TextField("Inbox note id", text: $inboxNoteId)
                    .font(.system(.caption, design: .monospaced))
            }

            Section("15Five") {
                Toggle("1-on-1 agendas as destinations", isOn: $fifteenFiveEnabled)
                    .onChange(of: fifteenFiveEnabled) { appDelegate.refreshDestinations() }
                LabeledContent("Account") {
                    if signingIn {
                        ProgressView().controlSize(.small)
                    } else if fifteenFiveAccount.isEmpty {
                        Button("Sign in…") { signInToFifteenFive() }
                    } else {
                        HStack {
                            Text(fifteenFiveAccount).foregroundStyle(.secondary)
                            Button("Sign out") { signOutOfFifteenFive() }
                        }
                    }
                }
                if let signInError {
                    Text(signInError).font(.caption).foregroundStyle(.red)
                }
                status(.fifteenFive)
                Button("Refresh now") { appDelegate.refreshDestinations() }
                Text("One row per person you have 1-on-1s with. Enter adds the capture as a talking point on your next 1-on-1 with them; the other person sees it. Needs 15Five MCP Access and Updates switched on in Agents Hub > Integrations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func status(_ id: ProviderID) -> some View {
        let state = appDelegate.store.state(id)
        return LabeledContent("Status") {
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(state.destinations.count) destinations")
                if let refreshed = state.lastRefresh {
                    Text("refreshed \(refreshed.formatted(date: .omitted, time: .standard))")
                        .foregroundStyle(.secondary)
                } else if id.isEnabled {
                    Text("not refreshed yet, showing cache")
                        .foregroundStyle(.orange)
                }
                if let error = state.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
            .font(.caption)
        }
    }

    private func signInToFifteenFive() {
        signingIn = true
        signInError = nil
        Task {
            defer { signingIn = false }
            do {
                try await signIn.run()
                await appDelegate.fifteenFive.reset()
                let whoami = try? await appDelegate.fifteenFive.callTool(name: "whoami", arguments: MCPJSON(value: [String: Any]()))
                fifteenFiveAccount = Self.accountName(whoami?.value) ?? "Signed in"
                fifteenFiveEnabled = true
                appDelegate.refreshDestinations()
            } catch FifteenFive.AuthError.cancelled {
            } catch {
                signInError = String(describing: error)
            }
        }
    }

    private func signOutOfFifteenFive() {
        Task {
            await FifteenFiveTokens.shared.clear()
            await appDelegate.fifteenFive.reset()
            fifteenFiveAccount = ""
            fifteenFiveEnabled = false
            appDelegate.refreshDestinations()
        }
    }

    private static func accountName(_ value: Any?) -> String? {
        guard let dict = value as? [String: Any] else { return value as? String }
        let user = dict["you"] as? [String: Any] ?? dict
        for key in ["full_name", "name", "display_name", "email"] {
            if let name = user[key] as? String, !name.isEmpty { return name }
        }
        return nil
    }
}
