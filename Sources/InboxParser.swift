import Foundation

struct TriageEntry: Identifiable, Hashable, Sendable {
    /// Text shown for editing: the source's own markup (header, bullet,
    /// timestamp, indentation) stripped.
    let body: String
    /// The entry exactly as it appears in the note: the removal key.
    let exactBlock: String
    /// The original timestamp, `2026-07-04 09:10` or date-only `2026-07-04`,
    /// so a filed entry keeps its capture time.
    let datetime: String?

    var id: String { exactBlock }
}

/// Splits the Inbox note into capture blocks. Blocks start with a
/// `**YYYY-MM-DD[ HH:mm]**` header (date-only headers exist in the live
/// note); blocks whose header carries a `→` marker (fallback-routed,
/// pending) are skipped, as are the `# Inbox` title and the trailing
/// `#inbox` tag line. Returns oldest-first for triage.
enum InboxParser {
    // Immutable after init; regex just isn't marked Sendable.
    private static nonisolated(unsafe) let headerRegex = /^\*\*\d{4}-\d{2}-\d{2}( \d{2}:\d{2})?\*\*.*$/

    static func isHeader(_ line: Substring) -> Bool {
        line.wholeMatch(of: headerRegex) != nil
    }

    static func parse(_ noteText: String) -> [TriageEntry] {
        let lines = noteText.split(separator: "\n", omittingEmptySubsequences: false)
        var entries: [TriageEntry] = []
        var currentHeader: Substring?
        var currentBody: [Substring] = []

        func flush() {
            guard let header = currentHeader else { return }
            defer {
                currentHeader = nil
                currentBody = []
            }
            // Trim trailing blank lines from the body (they are separators).
            var body = currentBody
            while let last = body.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                body.removeLast()
            }
            // Skip already-routed blocks (fallback marker in the header).
            guard !header.contains("→") else { return }
            let bodyText = body.joined(separator: "\n")
            let exact = bodyText.isEmpty ? String(header) : header + "\n" + bodyText
            let datetime = header.firstMatch(of: /\*\*(\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2})?)\*\*/).map { String($0.1) }
            entries.append(TriageEntry(body: bodyText, exactBlock: exact, datetime: datetime))
        }

        for line in lines {
            if isHeader(line) {
                flush()
                currentHeader = line
            } else if currentHeader != nil {
                // The trailing tag line belongs to the note, not the block.
                if isTagOnlyLine(line) { continue }
                currentBody.append(line)
            }
        }
        flush()

        // Note is newest-on-top; triage goes oldest-first.
        return entries.reversed()
    }

    static func isTagOnlyLine(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return false }
        return trimmed.split(separator: " ").allSatisfy { $0.hasPrefix("#") && $0.count > 1 }
    }
}
