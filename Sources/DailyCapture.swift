import AppKit
import Foundation

enum DailyCapture {
    static let templateKey = "uriTemplate"
    static let defaultTemplate =
        "octarine://daily?date=today&content=-%20%28{time}%29%20{content}&position=bottom&separator=%0A&openAfter=false"

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

    static func send(_ text: String) {
        let template = currentTemplate()
        let now = Date()

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?#+")

        let content = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
        let time = timeFormatter.string(from: now).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let date = dateFormatter.string(from: now).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""

        let uri = template
            .replacingOccurrences(of: "{content}", with: content)
            .replacingOccurrences(of: "{time}", with: time)
            .replacingOccurrences(of: "{date}", with: date)

        guard let url = URL(string: uri) else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        NSWorkspace.shared.open(url, configuration: config, completionHandler: nil)
    }

    private static func currentTemplate() -> String {
        let stored = UserDefaults.standard.string(forKey: templateKey) ?? ""
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultTemplate : trimmed
    }
}
