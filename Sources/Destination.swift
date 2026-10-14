import Foundation

/// One routable target in the picker. `ref` is the provider's own id for it
/// (a Bear note id, a 15Five person id). The Inbox is synthetic: in capture
/// mode it files to the Bear Inbox note, in triage it keeps the item there.
struct Destination: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case inbox, project, personal, person, list, agenda, oneOnOne

        var label: String { self == .oneOnOne ? "15Five" : rawValue }
    }

    let provider: ProviderID
    /// nil only for the synthetic Inbox row.
    let ref: String?
    let title: String
    let kind: Kind
    var lastModified: Date?

    /// Provider-qualified, so the same person in Bear and 15Five never collide.
    var id: String { ref.map { "\(provider.rawValue):\($0)" } ?? "inbox" }

    static let inbox = Destination(provider: .bear, ref: nil, title: "Inbox", kind: .inbox)
}

/// Precomputed normalization so per-keystroke ranking allocates nothing.
struct IndexedDestination: Sendable {
    let destination: Destination
    let normalizedTitle: String
    let words: [String]

    init(_ destination: Destination) {
        self.destination = destination
        normalizedTitle = destination.title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        words = normalizedTitle
            .split(whereSeparator: { " -/&,".contains($0) })
            .map(String.init)
    }
}
