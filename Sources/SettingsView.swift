import SwiftUI

struct SettingsView: View {
    @AppStorage(DailyCapture.templateKey) private var uriTemplate = DailyCapture.defaultTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("URI Template")
                .font(.headline)

            Text("The URI opened when you capture. Use the placeholders below to inject the captured text and current time. All substituted values are URL-encoded.")
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
        .padding(24)
        .frame(width: 560)
    }
}
