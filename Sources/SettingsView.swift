import SwiftUI

struct SettingsView: View {
    @AppStorage(DailyCapture.templateKey) private var uriTemplate = DailyCapture.defaultTemplate
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            uriTemplateSection
            Divider()
            launchAtLoginSection
        }
        .padding(24)
        .frame(width: 560)
    }

    private var uriTemplateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("URI Template")
                .font(.headline)

            Text("The URI opened when you capture. The default prepends the capture to your Bear “Inbox” note; edit the `id=` value to target a different note. Use the placeholders below to inject the captured text and current time. All substituted values are URL-encoded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $uriTemplate)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.separator)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Placeholders").font(.caption.weight(.semibold))
                Text("`{content}` — captured text")
                Text("`{time}` — `HH:mm`")
                Text("`{date}` — `yyyy-MM-dd`")
                Text("`{datetime}` — `2026-06-15 21:30`")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Reset to Default") {
                    uriTemplate = DailyCapture.defaultTemplate
                }
            }
        }
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            } else {
                Text("Capture must live in a stable location (e.g. /Applications) for this to survive reboots.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
