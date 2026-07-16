import Foundation

/// One routable target in the picker: a Bear tag leaf plus the note the
/// capture lands in. The Inbox and the general-reference note are synthetic
/// destinations so the picker has a single row type.
struct Destination: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case project, person, personal, reference, inbox, general

        var label: String {
            switch self {
            case .general: "reference"
            default: rawValue
            }
        }
    }

    let tag: String
    let kind: Kind
    var rootNoteId: String?
    var rootNoteTitle: String?
    var lastModified: Date?
    var paused: Bool = false
    /// false = discovered by the tag scan but not (yet) listed in the
    /// Capture registry note.
    var registered: Bool = true

    var id: String { tag }

    var leafName: String {
        switch kind {
        case .inbox: "inbox"
        case .general: "general reference"
        default: tag.split(separator: "/").last.map(String.init) ?? tag
        }
    }

    static let inbox = Destination(tag: "inbox", kind: .inbox)

    static func general(noteId: String, title: String?) -> Destination {
        Destination(tag: "general", kind: .general, rootNoteId: noteId, rootNoteTitle: title)
    }

    static func kind(forTag tag: String) -> Kind? {
        if tag.hasPrefix("project/") { return .project }
        if tag.hasPrefix("person/") { return .person }
        if tag.hasPrefix("personal/") { return .personal }
        if tag == "reference" { return .reference }
        return nil
    }
}

/// Precomputed normalization so per-keystroke ranking allocates nothing.
struct IndexedDestination: Sendable {
    let destination: Destination
    let normalizedLeaf: String
    let normalizedFull: String
    let words: [String]

    init(_ destination: Destination) {
        self.destination = destination
        let fold: (String) -> String = {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
        normalizedLeaf = fold(destination.leafName)
        normalizedFull = fold(destination.tag)
        words = normalizedFull
            .split(whereSeparator: { "/- ".contains($0) })
            .map(String.init)
    }
}
