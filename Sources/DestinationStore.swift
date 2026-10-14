import Foundation
import Observation

/// In-memory destination list backing the picker, merged across enabled
/// providers. Loaded synchronously from per-provider JSON caches at launch
/// (the picker is never empty), refreshed asynchronously at launch, on every
/// panel show, and on demand. A provider that fails keeps its cached rows.
@MainActor
@Observable
final class DestinationStore {
    nonisolated static let inboxNoteIdKey = "inboxNoteID"
    nonisolated static let defaultInboxNoteId = "E01000CB-BE7D-4FCB-8340-BBE23A4569B9"

    struct ProviderState {
        var destinations: [Destination] = []
        var lastRefresh: Date?
        var lastError: String?
        var refreshing = false
    }

    let providers: [any DestinationProvider]
    private(set) var states: [ProviderID: ProviderState] = [:]
    private(set) var destinations: [Destination] = []
    private(set) var indexed: [IndexedDestination] = []

    /// Most-recently-used destination ids, most recent first, unique.
    private(set) var usage: [String] = []
    private(set) var usageIndex: [String: Int] = [:]

    init(providers: [any DestinationProvider]) {
        self.providers = providers
    }

    nonisolated static var inboxNoteId: String {
        let stored = UserDefaults.standard.string(forKey: inboxNoteIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultInboxNoteId : stored
    }

    func provider(_ id: ProviderID) -> (any DestinationProvider)? {
        providers.first { $0.id == id }
    }

    func state(_ id: ProviderID) -> ProviderState {
        states[id] ?? ProviderState()
    }

    // MARK: - Cache

    private static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Capture", isDirectory: true)
    }
    private static func cacheURL(_ id: ProviderID) -> URL {
        supportDir.appendingPathComponent("destinations-\(id.rawValue).json")
    }
    // v3: ids became provider-qualified (`bear:<note id>`).
    private static var usageURL: URL { supportDir.appendingPathComponent("usage-v3.json") }

    func loadCache() {
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for provider in providers {
            if let data = try? Data(contentsOf: Self.cacheURL(provider.id)),
               let cached = try? decoder.decode([Destination].self, from: data) {
                states[provider.id, default: ProviderState()].destinations = cached
            }
        }
        if let data = try? Data(contentsOf: Self.usageURL),
           let ids = try? decoder.decode([String].self, from: data) {
            usage = ids
            rebuildUsageIndex()
        }
        merge()
    }

    private func persistCache(_ id: ProviderID) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(state(id).destinations) {
            try? data.write(to: Self.cacheURL(id), options: .atomic)
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

    func refresh() {
        for provider in providers where provider.id.isEnabled {
            refresh(provider)
        }
        merge() // drops rows of providers switched off since the last refresh
    }

    private func refresh(_ provider: any DestinationProvider) {
        let id = provider.id
        guard !state(id).refreshing else { return }
        states[id, default: ProviderState()].refreshing = true
        Task { [weak self] in
            do {
                let fresh = try await provider.listDestinations()
                guard let self else { return }
                self.states[id, default: ProviderState()].destinations = fresh
                self.states[id]?.lastRefresh = Date()
                self.states[id]?.lastError = nil
                self.persistCache(id)
                self.merge()
            } catch {
                self?.states[id, default: ProviderState()].lastError = String(describing: error)
            }
            self?.states[id]?.refreshing = false
        }
    }

    private func merge() {
        destinations = Self.merged(states.filter { $0.key.isEnabled }.map(\.value.destinations))
        indexed = destinations.map(IndexedDestination.init)
    }

    /// Most recently modified first across all providers.
    nonisolated static func merged(_ lists: [[Destination]]) -> [Destination] {
        lists.flatMap { $0 }
            .sorted { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
    }
}
