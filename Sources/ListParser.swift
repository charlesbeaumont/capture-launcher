import Foundation

/// Splits a `#list` note into its items. An item is a top-level bullet plus
/// the indented lines under it. The leading timestamp, in either form the
/// lists carry (`2026-07-23 10:45 — text` by hand, `**2026-07-23 10:45**: text`
/// from Capture), becomes the entry's datetime. Returns note order: lists
/// append at the bottom, so that is oldest first.
enum ListParser {
    // Immutable after init; regex just isn't marked Sendable.
    private static nonisolated(unsafe) let stampRegex =
        /^(?:\*\*(\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2})?)\*\*:?|(\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2})?) [—–-])\s*/

    static func parse(_ noteText: String) -> [TriageEntry] {
        var entries: [TriageEntry] = []
        var item: [Substring] = []

        func flush() {
            guard let first = item.first else { return }
            defer { item = [] }
            var text = first.dropFirst(2) // "- " or "* "
            var datetime: String?
            if let match = text.prefixMatch(of: stampRegex) {
                datetime = String(match.1 ?? match.2 ?? "")
                text = text[match.range.upperBound...]
            }
            let body = ([text] + item.dropFirst().map(dedented)).joined(separator: "\n")
            entries.append(TriageEntry(body: body, exactBlock: item.joined(separator: "\n"), datetime: datetime))
        }

        for line in noteText.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush()
                item = [line]
            } else if !item.isEmpty, line.first == " " || line.first == "\t",
                      !line.trimmingCharacters(in: .whitespaces).isEmpty {
                item.append(line)
            } else {
                flush()
            }
        }
        flush()
        return entries
    }

    /// One indent level off, so nested bullets stay nested when refiled.
    private static func dedented(_ line: Substring) -> Substring {
        if line.hasPrefix("\t") { return line.dropFirst() }
        if line.hasPrefix("  ") { return line.dropFirst(2) }
        return line.drop { $0 == " " }
    }
}
