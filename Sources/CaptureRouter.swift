import Foundation

/// Orchestrates all capture writes. Callers are synchronous and optimistic —
/// the panel hides / triage advances immediately; every method runs its work
/// in a fire-and-forget Task. Destinations are written by their provider; the
/// Inbox stays Bear's. Invariant: a capture is NEVER lost — any failure
/// degrades to the x-callback Inbox write with a marker plus a notification.
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
                Self.logRouting(source: "capture", text: text, destination: "Inbox", noteId: inboxId)
            } catch {
                // Fallback: the original x-callback path.
                DailyCapture.send(text)
                Notify.failure("Inbox write via bearcli failed — sent via Bear URL instead. \(error)")
            }
        }
    }

    /// Routed capture: lands verbatim in the destination note's section.
    func file(text: String, to destination: Destination, timestamp: Date = Date()) {
        store.recordUsage(destination)
        let datetime = Self.datetimeFormatter.string(from: timestamp)
        Task {
            await fileAndVerify(text: text, to: destination, datetime: datetime, source: "capture")
        }
    }

    /// Triage decision: file the (possibly edited) text under its original
    /// Inbox timestamp, then remove the block from the Inbox. The Inbox row
    /// means "keep it there", so nothing moves.
    func triageRoute(entry: InboxEntry, editedText: String, to destination: Destination) {
        guard destination.kind != .inbox else { return }
        store.recordUsage(destination)
        let datetime = entry.datetime ?? Self.datetimeFormatter.string(from: Date())
        Task {
            let filed = await fileAndVerify(
                text: editedText,
                to: destination,
                datetime: datetime,
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
            Self.logRouting(source: "discard", text: entry.body, destination: "-", noteId: DestinationStore.inboxNoteId)
        }
    }

    // MARK: - Filing

    @discardableResult
    private func fileAndVerify(
        text: String,
        to destination: Destination,
        datetime: String,
        source: String
    ) async -> Bool {
        let label = Self.markerLabel(destination)
        guard let provider = store.provider(destination.provider), destination.provider.isEnabled else {
            fallbackToInbox(text: text, destination: label,
                            reason: "\(destination.provider.displayName) is switched off")
            return false
        }
        do {
            try await provider.file(text: text, datetime: datetime, to: destination, requestID: UUID())
            Self.logRouting(source: source, text: text, destination: label, noteId: destination.ref)
            return true
        } catch {
            fallbackToInbox(text: text, destination: label, reason: String(describing: error))
            return false
        }
    }

    /// The title the `review-captures` skill routes by; non-Bear destinations
    /// name their system so the parked capture says where it was going.
    nonisolated static func markerLabel(_ destination: Destination) -> String {
        destination.provider == .bear
            ? destination.title
            : "\(destination.title) (\(destination.provider.displayName))"
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

    private func fallbackToInbox(text: String, destination: String, reason: String) {
        DailyCapture.send(text, marker: destination)
        Notify.failure("Filing to \(destination) failed — capture parked in Inbox with a marker. \(reason)")
        Self.logRouting(source: "fallback", text: text, destination: destination, noteId: nil)
    }

    // MARK: - Pure text transforms

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

    nonisolated static func logRouting(source: String, text: String, destination: String, noteId: String?) {
        struct Record: Codable {
            let ts: String
            let source: String
            let text: String
            let destination: String
            let noteId: String?
        }
        let record = Record(
            ts: ISO8601DateFormatter().string(from: Date()),
            source: source, text: text, destination: destination, noteId: noteId
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
