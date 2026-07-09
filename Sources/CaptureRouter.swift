import Foundation

/// Orchestrates all capture writes. Callers are synchronous and optimistic —
/// the panel hides / triage advances immediately; every method runs its Bear
/// work in a fire-and-forget Task. Invariant: a capture is NEVER lost — any
/// bearcli failure degrades to the x-callback Inbox write with a marker plus
/// a notification.
@MainActor
final class CaptureRouter {
    private let bear: BearCLI
    private let store: DestinationStore

    init(bear: BearCLI, store: DestinationStore) {
        self.bear = bear
        self.store = store
    }

    private static let datetimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    // MARK: - Public entry points (all optimistic)

    /// Plain capture to the Inbox note, prepended under the H1 — same block
    /// format the x-callback template produced.
    func captureToInbox(text: String, timestamp: Date = Date()) {
        let block = "**\(Self.datetimeFormatter.string(from: timestamp))**\n\(text)"
        let inboxId = DestinationStore.inboxNoteId
        Task {
            do {
                try await bear.casEdit(noteId: inboxId) { content in
                    Self.prepending(block: block, to: content)
                }
                Self.logRouting(source: "capture", text: text, tag: "inbox", noteId: inboxId)
            } catch {
                // Fallback: the original x-callback path.
                DailyCapture.send(text)
                Notify.failure("Inbox write via bearcli failed — sent via Bear URL instead. \(error)")
            }
        }
    }

    /// Routed capture: lands in the destination note's ## Captured section
    /// immediately, then the filing agent repositions it.
    func file(text: String, to destination: Destination, timestamp: Date = Date()) {
        store.recordUsage(tag: destination.tag)
        Task {
            await fileAndVerify(text: text, to: destination, timestamp: timestamp, source: "capture")
        }
    }

    /// Triage decision: file the (possibly edited) text, then remove the
    /// original block from the Inbox.
    func triageRoute(entry: InboxEntry, editedText: String, to destination: Destination) {
        store.recordUsage(tag: destination.tag)
        Task {
            let filed = await fileAndVerify(
                text: editedText,
                to: destination,
                timestamp: Date(),
                source: "triage"
            )
            guard filed else { return } // fallback already notified; block stays put
            await removeInboxBlock(entry)
        }
    }

    /// Triage discard: remove the block, file nothing.
    func triageDiscard(entry: InboxEntry) {
        Task {
            await removeInboxBlock(entry)
            Self.logRouting(source: "discard", text: entry.body, tag: "-", noteId: DestinationStore.inboxNoteId)
        }
    }

    // MARK: - Filing

    @discardableResult
    private func fileAndVerify(
        text: String,
        to destination: Destination,
        timestamp: Date,
        source: String
    ) async -> Bool {
        guard let noteId = destination.rootNoteId else {
            fallbackToInbox(text: text, tag: destination.tag,
                            reason: "destination \(destination.tag) has no target note")
            return false
        }
        let entryLine = Self.capturedEntry(
            text: text,
            datetime: Self.datetimeFormatter.string(from: timestamp)
        )
        do {
            try await bear.casEdit(noteId: noteId) { content in
                Self.insertingCapture(entryLine, into: content)
            }
            Self.logRouting(source: source, text: text, tag: destination.tag, noteId: noteId)
            FilingAgent.spawn(
                noteId: noteId,
                noteTitle: destination.rootNoteTitle ?? destination.leafName,
                tag: destination.tag,
                text: text,
                datetime: Self.datetimeFormatter.string(from: timestamp)
            )
            return true
        } catch {
            fallbackToInbox(text: text, tag: destination.tag, reason: String(describing: error))
            return false
        }
    }

    private func removeInboxBlock(_ entry: InboxEntry) async {
        do {
            try await bear.casEdit(noteId: DestinationStore.inboxNoteId) { content in
                Self.removingBlock(entry.exactBlock, from: content)
            }
        } catch {
            Notify.failure("Could not remove the inbox block — it may reappear in triage. \(error)")
        }
    }

    private func fallbackToInbox(text: String, tag: String, reason: String) {
        // Backtick-wrapped so Bear does not tag the Inbox note with it.
        DailyCapture.send(text, marker: tag)
        Notify.failure("Filing to \(tag) failed — capture parked in Inbox with a marker. \(reason)")
        Self.logRouting(source: "fallback", text: text, tag: tag, noteId: nil)
    }

    // MARK: - Pure text transforms

    /// `- 2026-07-04 09:12 — text` with multi-line bodies indented under the bullet.
    nonisolated static func capturedEntry(text: String, datetime: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let joined = lines.joined(separator: "\n  ")
        return "- \(datetime) — \(joined)"
    }

    /// Prepend a capture block directly under the note's H1 (or at the very
    /// top when there is none), blank-line separated from what follows.
    nonisolated static func prepending(block: String, to content: String) -> String {
        if content.hasPrefix("# "), let firstBreak = content.firstIndex(of: "\n") {
            let head = content[..<firstBreak]
            let rest = content[content.index(after: firstBreak)...]
            return "\(head)\n\(block)\n\n\(rest)"
        }
        return "\(block)\n\n\(content)"
    }

    /// Insert a captured entry at the end of the `## Captured` section,
    /// creating the section above the trailing tag block when missing.
    nonisolated static func insertingCapture(_ entry: String, into content: String) -> String {
        if let sectionRange = content.range(of: "## Captured") {
            // Section ends at the next "## " heading or the trailing tag block.
            let afterSection = content[sectionRange.upperBound...]
            var insertionIndex: String.Index
            if let nextHeading = afterSection.range(of: "\n## ") {
                insertionIndex = nextHeading.lowerBound
            } else if let tagStart = trailingTagBlockStart(of: content),
                      tagStart > sectionRange.upperBound {
                insertionIndex = tagStart
            } else {
                insertionIndex = content.endIndex
            }
            // Back off over blank lines so the entry joins the list tightly.
            var head = String(content[..<insertionIndex])
            let tail = String(content[insertionIndex...])
            while head.hasSuffix("\n") { head.removeLast() }
            let separator = tail.hasPrefix("\n") ? "" : "\n"
            return head + "\n" + entry + separator + tail
        }

        // No section yet: create it above the trailing tag block.
        let section = "## Captured\n\n\(entry)"
        if let tagStart = trailingTagBlockStart(of: content) {
            var head = String(content[..<tagStart])
            let tail = String(content[tagStart...])
            while head.hasSuffix("\n") { head.removeLast() }
            return head + "\n\n" + section + "\n\n" + tail
        }
        var trimmed = content
        while trimmed.hasSuffix("\n") { trimmed.removeLast() }
        return trimmed + "\n\n" + section + "\n"
    }

    /// Index of the first line of the trailing tag-only block (Bear keeps
    /// `#project/x`-style tags as the last line(s) of a note), or nil.
    nonisolated static func trailingTagBlockStart(of content: String) -> String.Index? {
        var lines: [(line: Substring, start: String.Index)] = []
        var lineStart = content.startIndex
        for index in content.indices {
            if content[index] == "\n" {
                lines.append((content[lineStart..<index], lineStart))
                lineStart = content.index(after: index)
            }
        }
        lines.append((content[lineStart...], lineStart))

        var tagBlockStart: String.Index?
        for (line, start) in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if tagBlockStart == nil { continue } // trailing blank lines
                break
            }
            if InboxParser.isTagOnlyLine(line) {
                tagBlockStart = start
            } else {
                break
            }
        }
        return tagBlockStart
    }

    /// Exact-string block removal. nil = not found (idempotent no-op:
    /// already removed by an earlier attempt or by hand).
    nonisolated static func removingBlock(_ block: String, from content: String) -> String? {
        for pattern in [block + "\n\n", block + "\n"] {
            if let range = content.range(of: pattern) {
                return collapseBlankRuns(content.replacingCharacters(in: range, with: ""))
            }
        }
        if let range = content.range(of: block) {
            return collapseBlankRuns(content.replacingCharacters(in: range, with: ""))
        }
        return nil
    }

    nonisolated private static func collapseBlankRuns(_ text: String) -> String {
        text.replacing(/\n{3,}/, with: "\n\n")
    }

    // MARK: - Routing log

    nonisolated private static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Capture/routings.jsonl")
    }

    nonisolated static func logRouting(source: String, text: String, tag: String, noteId: String?) {
        struct Record: Codable {
            let ts: String
            let source: String
            let text: String
            let tag: String
            let noteId: String?
        }
        let record = Record(
            ts: ISO8601DateFormatter().string(from: Date()),
            source: source, text: text, tag: tag, noteId: noteId
        )
        guard var data = try? JSONEncoder().encode(record) else { return }
        data.append(Data("\n".utf8))
        let url = logURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
