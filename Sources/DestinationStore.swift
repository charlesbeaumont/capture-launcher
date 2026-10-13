import Foundation
import Observation

/// In-memory destination list backing the picker. Loaded synchronously from a
/// JSON cache at launch (the picker is never empty), refreshed asynchronously
/// via bearcli at launch, on every panel show, and on demand. Every note
/// carrying a routable type tag is a destination; see `Destination.kind`.
@MainActor
@Observable
final class DestinationStore {
    nonisolated static let inboxNoteIdKey = "inboxNoteID"
    nonisolated static let defaultInboxNoteId = "E01000CB-BE7D-4FCB-8340-BBE23A4569B9"

    private(set) var destinations: [Destination] = []
    private(set) var indexed: [IndexedDestination] = []
    private(set) var lastRefresh: Date?
    private(set) var lastError: String?
    private(set) var refreshing = false

    /// Most-recently-used destination ids, most recent first, unique.
    private(set) var usage: [String] = []
    private(set) var usageIndex: [String: Int] = [:]

    nonisolated static var inboxNoteId: String {
        let stored = UserDefaults.standard.string(forKey: inboxNoteIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultInboxNoteId : stored
    }

    // MARK: - Cache

    private static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Capture", isDirectory: true)
    }
    // v2: v1 files were keyed by nested tags (`project/x`) that no longer exist.
    private static var cacheURL: URL { supportDir.appendingPathComponent("destinations-v2.json") }
    private static var usageURL: URL { supportDir.appendingPathComponent("usage-v2.json") }

    private struct Cache: Codable {
        var destinations: [Destination]
        var savedAt: Date
    }

    func loadCache() {
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: Self.cacheURL),
           let cache = try? decoder.decode(Cache.self, from: data) {
            publish(cache.destinations, refreshedAt: nil)
        }
        if let data = try? Data(contentsOf: Self.usageURL),
           let tags = try? decoder.decode([String].self, from: data) {
            usage = tags
            rebuildUsageIndex()
        }
    }

    private func persistCache() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let cache = Cache(destinations: destinations, savedAt: Date())
        if let data = try? encoder.encode(cache) {
            try? data.write(to: Self.cacheURL, options: .atomic)
        }
    }

    func recordUsage(_ destination: Destination) {
        usage.removeAll { $0 == destination.id }
        usage.insert(destination.id, at: 0)
        if usage.count > 50 { usage.removeLast(usage.count - 50) }
        rebuildUsageIndex()
        if let data = try? JSONEncoder().encode(usage) {
            try? data.write(to: Self.usageURL, options: .atomic)
        }
    }

    private func rebuildUsageIndex() {
        usageIndex = Dictionary(uniqueKeysWithValues: usage.enumerated().map { ($1, $0) })
    }

    // MARK: - Refresh

    func refresh(using bear: BearCLI) {
        guard !refreshing else { return }
        refreshing = true
        Task { [weak self] in
            do {
                let notes = try await bear.listNotes()
                guard let self else { return }
                self.publish(Self.build(notes: notes), refreshedAt: Date())
                self.lastError = nil
                self.persistCache()
            } catch {
                self?.lastError = String(describing: error)
            }
            self?.refreshing = false
        }
    }

    private func publish(_ dests: [Destination], refreshedAt: Date?) {
        destinations = dests
        indexed = dests.map(IndexedDestination.init)
        if let refreshedAt { lastRefresh = refreshedAt }
    }

    // MARK: - Building the destination list (pure, testable)

    /// One destination per note carrying a routable type tag, most recently
    /// modified first. The Inbox note is excluded: it is the synthetic row.
    nonisolated static func build(notes: [BearCLI.NoteMeta]) -> [Destination] {
        notes
            .compactMap { note -> Destination? in
                guard note.id != inboxNoteId,
                      let kind = Destination.kind(forTags: note.tags) else { return nil }
                return Destination(noteId: note.id, title: note.title, kind: kind,
                                   lastModified: note.modified)
            }
            .sorted { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
    }
}
