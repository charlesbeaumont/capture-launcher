import Foundation

struct InboxEntry: Identifiable, Hashable, Sendable {
    /// The header line as found, e.g. "**2026-07-04 09:10**".
    let header: String
    /// Body text without the header, trailing whitespace trimmed. May be empty.
    let body: String
    /// Header + body exactly as they appear in the note — the removal key.
    let exactBlock: String

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

    static func parse(_ noteText: String) -> [InboxEntry] {
        let lines = noteText.split(separator: "\n", omittingEmptySubsequences: false)
        var entries: [InboxEntry] = []
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
            entries.append(InboxEntry(header: String(header), body: bodyText, exactBlock: exact))
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
