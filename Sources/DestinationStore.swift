import Foundation
import Observation

/// In-memory destination list backing the picker. Loaded synchronously from a
/// JSON cache at launch (the picker is never empty), refreshed asynchronously
/// via bearcli at launch, on every panel show, and on demand. The Capture
/// registry note is authoritative for paused/active status and the
/// general-reference target; the tag scan discovers new tags.
@MainActor
@Observable
final class DestinationStore {
    static let registryTitleKey = "registryNoteTitle"
    static let defaultRegistryTitle = "Capture registry"
    static let inboxNoteIdKey = "inboxNoteID"
    static let defaultInboxNoteId = "E01000CB-BE7D-4FCB-8340-BBE23A4569B9"

    private(set) var destinations: [Destination] = []
    private(set) var indexed: [IndexedDestination] = []
    private(set) var generalReference: Destination?
    private(set) var lastRefresh: Date?
    private(set) var lastError: String?
    private(set) var registryFound = false
    private(set) var refreshing = false

    /// Most-recently-used destination tags, most recent first, unique.
    private(set) var usage: [String] = []
    private(set) var usageIndex: [String: Int] = [:]

    static var inboxNoteId: String {
        let stored = UserDefaults.standard.string(forKey: inboxNoteIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultInboxNoteId : stored
    }

    static var registryTitle: String {
        let stored = UserDefaults.standard.string(forKey: registryTitleKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultRegistryTitle : stored
    }

    // MARK: - Cache

    private static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Capture", isDirectory: true)
    }
    private static var cacheURL: URL { supportDir.appendingPathComponent("destinations.json") }
    private static var usageURL: URL { supportDir.appendingPathComponent("usage.json") }

    private struct Cache: Codable {
        var destinations: [Destination]
        var generalReference: Destination?
        var savedAt: Date
    }

    func loadCache() {
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: Self.cacheURL),
           let cache = try? decoder.decode(Cache.self, from: data) {
            publish(cache.destinations, general: cache.generalReference, refreshedAt: nil)
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
        let cache = Cache(destinations: destinations, generalReference: generalReference, savedAt: Date())
        if let data = try? encoder.encode(cache) {
            try? data.write(to: Self.cacheURL, options: .atomic)
        }
    }

    func recordUsage(tag: String) {
        usage.removeAll { $0 == tag }
        usage.insert(tag, at: 0)
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
                let registryTitle = Self.registryTitle
                let registryNote = notes.first {
                    $0.title.compare(registryTitle, options: .caseInsensitive) == .orderedSame
                }
                var registryContent: String?
                if let registryNote {
                    registryContent = try await bear.readNote(id: registryNote.id).content
                }
                guard let self else { return }
                let (dests, general) = Self.build(
                    notes: notes,
                    registryContent: registryContent
                )
                self.registryFound = registryContent != nil
                self.publish(dests, general: general, refreshedAt: Date())
                self.lastError = nil
                self.persistCache()
            } catch {
                self?.lastError = String(describing: error)
            }
            self?.refreshing = false
        }
    }

    private func publish(_ dests: [Destination], general: Destination?, refreshedAt: Date?) {
        destinations = dests
        generalReference = general
        indexed = dests.map(IndexedDestination.init)
        if let refreshedAt { lastRefresh = refreshedAt }
    }

    // MARK: - Building the destination list (pure, testable)

    struct RegistryEntry {
        let tag: String
        let paused: Bool
        let explicitNoteId: String?
    }

    nonisolated static func parseRegistry(_ content: String) -> (entries: [RegistryEntry], generalReferenceId: String?) {
        var entries: [RegistryEntry] = []
        var generalId: String?
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("general-reference:") {
                let value = line.dropFirst("general-reference:".count)
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { generalId = value }
                continue
            }
            guard line.hasPrefix("- ") else { continue }
            var rest = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            var explicitId: String?
            if let arrow = rest.range(of: "→") {
                explicitId = rest[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
                rest = rest[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            let paused = rest.contains("!paused")
            rest = rest.replacingOccurrences(of: "!paused", with: "").trimmingCharacters(in: .whitespaces)
            let tag = rest.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            guard !tag.isEmpty else { continue }
            entries.append(RegistryEntry(tag: tag, paused: paused, explicitNoteId: explicitId))
        }
        return (entries, generalId)
    }

    nonisolated static func build(
        notes: [BearCLI.NoteMeta],
        registryContent: String?
    ) -> (destinations: [Destination], general: Destination?) {
        // Tag scan: tag → notes carrying it (tags come back "#project/x").
        var notesByTag: [String: [BearCLI.NoteMeta]] = [:]
        for note in notes {
            for rawTag in note.tags {
                let tag = rawTag.hasPrefix("#") ? String(rawTag.dropFirst()) : rawTag
                notesByTag[tag, default: []].append(note)
            }
        }

        // Leaves only: drop tags that are a strict prefix (+ "/") of another tag.
        let allTags = Set(notesByTag.keys)
        var scanned: [String: Destination] = [:]
        for (tag, tagNotes) in notesByTag {
            guard let kind = Destination.kind(forTag: tag) else { continue }
            guard !allTags.contains(where: { $0 != tag && $0.hasPrefix(tag + "/") }) else { continue }
            let root = rootNote(among: tagNotes)
            scanned[tag] = Destination(
                tag: tag,
                kind: kind,
                rootNoteId: root?.id,
                rootNoteTitle: root?.title,
                lastModified: tagNotes.compactMap(\.modified).max(),
                registered: false
            )
        }

        var result: [String: Destination] = scanned
        var general: Destination?

        if let registryContent {
            let (entries, generalId) = parseRegistry(registryContent)
            for entry in entries {
                if var dest = result[entry.tag] {
                    dest.registered = true
                    dest.paused = entry.paused
                    if let explicit = entry.explicitNoteId {
                        dest.rootNoteId = explicit
                        dest.rootNoteTitle = notes.first { $0.id == explicit }?.title
                    }
                    result[entry.tag] = dest
                } else if let explicit = entry.explicitNoteId,
                          let kind = Destination.kind(forTag: entry.tag) {
                    // Registry-only entry with an explicit target note.
                    result[entry.tag] = Destination(
                        tag: entry.tag,
                        kind: kind,
                        rootNoteId: explicit,
                        rootNoteTitle: notes.first { $0.id == explicit }?.title,
                        lastModified: notes.first { $0.id == explicit }?.modified,
                        paused: entry.paused,
                        registered: true
                    )
                }
            }
            if let generalId {
                general = .general(
                    noteId: generalId,
                    title: notes.first { $0.id == generalId }?.title
                )
            }
        } else {
            // No registry yet: everything the scan found counts as registered.
            for (tag, var dest) in result {
                dest.registered = true
                result[tag] = dest
            }
        }

        let sorted = result.values
            .filter { $0.rootNoteId != nil }
            .sorted {
                ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast)
            }
        return (sorted, general)
    }

    /// Root note = title without a " - <topic>" suffix; among several,
    /// the most recently modified; fallback: most recently modified overall.
    nonisolated private static func rootNote(among notes: [BearCLI.NoteMeta]) -> BearCLI.NoteMeta? {
        let byRecency = notes.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        return byRecency.first { !$0.title.contains(" - ") } ?? byRecency.first
    }
}
