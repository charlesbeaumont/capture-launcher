import Foundation

/// One routable Bear note. The second brain uses flat type tags (`#project`,
/// `#person`, …) and identifies a note by its title, so a destination is a
/// note id, a title and a kind. The Inbox is synthetic: in capture mode it
/// files to the Inbox note, in triage it keeps the item where it is.
struct Destination: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case inbox, project, personal, person, list, agenda

        var label: String { rawValue }

        /// Agendas collect topics; every other note collects captures.
        var section: String { self == .agenda ? "## Topics" : "## Captures" }

        /// Project, personal and person notes keep captures newest first.
        /// Lists and agendas are running lists, appended at the bottom.
        var newestFirst: Bool {
            switch self {
            case .project, .personal, .person: true
            case .inbox, .list, .agenda: false
            }
        }
    }

    /// nil only for the synthetic Inbox row.
    let noteId: String?
    let title: String
    let kind: Kind
    var lastModified: Date?

    var id: String { noteId ?? "inbox" }

    static let inbox = Destination(noteId: nil, title: "Inbox", kind: .inbox)

    /// `#archive`, `#unsorted`, `#reference` and the rest are never routable.
    static func kind(forTags tags: [String]) -> Kind? {
        for raw in tags {
            switch raw.hasPrefix("#") ? String(raw.dropFirst()) : raw {
            case "project": return .project
            case "personal": return .personal
            case "person": return .person
            case "list": return .list
            case "agenda": return .agenda
            default: continue
            }
        }
        return nil
    }
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
