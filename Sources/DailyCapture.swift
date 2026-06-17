import AppKit
import Foundation

enum DailyCapture {
    static let templateKey = "uriTemplate"

    // Prepends a capture block to Bear's pinned "Inbox" note via the add-text
    // x-callback-url. Decodes to:
    //
    //   **2026-06-15 21:30**
    //   the capture text
    //
    // Newest capture ends up on top (mode=prepend). The text ends with a SINGLE
    // trailing %0A — Bear's prepend inserts its own separator newline before the
    // existing content, so one %0A here yields exactly one blank line between
    // consecutive captures (verified against Bear; two %0A produced a double gap).
    // open_note/show_window=no so Bear never steals focus. The note is targeted
    // by its stable id; edit the `id=` value here (or in Settings) to retarget,
    // or swap to `title=Inbox`.
    static let defaultTemplate =
        "bear://x-callback-url/add-text?id=E01000CB-BE7D-4FCB-8340-BBE23A4569B9&mode=prepend&open_note=no&show_window=no&text=**{datetime}**%0A{content}%0A"

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let datetimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func send(_ text: String) {
        let template = currentTemplate()
        let now = Date()

        // Strict: encode every non-alphanumeric in dynamic values. urlQueryAllowed
        // leaves &, #, = unescaped, which corrupts the URL when captured content
        // contains them. Bear decodes the percent-escapes back losslessly.
        let allowed = CharacterSet.alphanumerics

        let content = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        let time = timeFormatter.string(from: now).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let date = dateFormatter.string(from: now).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let datetime = datetimeFormatter.string(from: now).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""

        let uri = template
            .replacingOccurrences(of: "{content}", with: content)
            .replacingOccurrences(of: "{time}", with: time)
            .replacingOccurrences(of: "{date}", with: date)
            .replacingOccurrences(of: "{datetime}", with: datetime)

        guard let url = URL(string: uri) else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        NSWorkspace.shared.open(url, configuration: config, completionHandler: nil)
    }

    private static func currentTemplate() -> String {
        let stored = UserDefaults.standard.string(forKey: templateKey) ?? ""
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        // Supersede any leftover Octarine template from before the Bear migration
        // so a stale stored value doesn't keep firing at the old target.
        if trimmed.isEmpty || trimmed.contains("octarine://") {
            return defaultTemplate
        }
        return trimmed
    }
}
