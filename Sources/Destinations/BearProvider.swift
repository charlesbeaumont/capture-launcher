import Foundation

/// Files into the Bear second brain through bearcli. Destinations are notes
/// with a routable flat type tag; a capture lands verbatim as one line in the
/// note's section, matching the `review-captures` skill.
struct BearProvider: DestinationProvider {
    let bear: BearCLI
    var id: ProviderID { .bear }

    func listDestinations() async throws -> [Destination] {
        Self.destinations(from: try await bear.listNotes())
    }

    func file(text: String, datetime: String, to destination: Destination, requestID: UUID) async throws {
        guard let noteId = destination.ref else { throw BearCLI.Failure.badOutput("no note for \(destination.title)") }
        let line = Self.captureLine(text: text, datetime: datetime)
        try await bear.casEdit(noteId: noteId) { content in
            Self.inserting(line, into: content, kind: destination.kind)
        }
    }

    // MARK: - Destinations (pure, testable)

    /// One destination per note carrying a routable type tag, most recently
    /// modified first. The Inbox note is excluded: it is the synthetic row.
    nonisolated static func destinations(from notes: [BearCLI.NoteMeta]) -> [Destination] {
        notes
            .compactMap { note -> Destination? in
                guard note.id != DestinationStore.inboxNoteId,
                      let kind = kind(forTags: note.tags) else { return nil }
                return Destination(provider: .bear, ref: note.id, title: note.title,
                                   kind: kind, lastModified: note.modified)
            }
            .sorted { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
    }

    /// `#archive`, `#unsorted`, `#reference` and the rest are never routable.
    nonisolated static func kind(forTags tags: [String]) -> Destination.Kind? {
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

    // MARK: - Note format (pure, testable)

    /// Agendas collect topics; every other note collects captures.
    nonisolated static func section(for kind: Destination.Kind) -> String {
        kind == .agenda ? "## Topics" : "## Captures"
    }

    /// Project, personal and person notes keep captures newest first. Lists
    /// and agendas are running lists, appended at the bottom.
    nonisolated static func newestFirst(_ kind: Destination.Kind) -> Bool {
        [.project, .personal, .person].contains(kind)
    }

    /// `- **2026-07-04 09:12**: text`, the second brain's capture line, with
    /// multi-line bodies indented under the bullet.
    nonisolated static func captureLine(text: String, datetime: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return "- **\(datetime)**: " + lines.joined(separator: "\n  ")
    }

    /// Insert `line` into the kind's section: at the top when the kind keeps
    /// newest first, at the bottom otherwise. A missing section is created
    /// above the trailing tag line, the only place the skills expect it.
    nonisolated static func inserting(_ line: String, into content: String, kind: Destination.Kind) -> String {
        let heading = section(for: kind)
        guard let headingRange = sectionHeadingRange(heading, in: content) else {
            let section = "\(heading)\n\n\(line)"
            if let tagStart = trailingTagBlockStart(of: content) {
                let head = trimmingTrailingNewlines(String(content[..<tagStart]))
                return head + "\n\n" + section + "\n\n" + content[tagStart...]
            }
            return trimmingTrailingNewlines(content) + "\n\n" + section + "\n"
        }

        let bodyStart = headingRange.upperBound
        let afterHeading = content[bodyStart...]
        var bodyEnd = afterHeading.range(of: "\n## ")?.lowerBound ?? content.endIndex
        if let tagStart = trailingTagBlockStart(of: content), tagStart > bodyStart, tagStart < bodyEnd {
            bodyEnd = tagStart
        }
        let body = String(content[bodyStart..<bodyEnd])
            .trimmingCharacters(in: .newlines)
        let newBody = body.isEmpty ? line : (newestFirst(kind) ? line + "\n" + body : body + "\n" + line)
        // The tail starts with "\n## " (next heading), a tag line, or is empty.
        let tail = content[bodyEnd...]
        let separator = tail.isEmpty || tail.hasPrefix("\n") ? "\n" : "\n\n"
        return content[..<bodyStart] + "\n\n" + newBody + separator + tail
    }

    /// The heading line, matched whole so `## Captures` never matches a
    /// longer heading that merely starts with it.
    nonisolated private static func sectionHeadingRange(_ heading: String, in content: String) -> Range<String.Index>? {
        var search = content.startIndex..<content.endIndex
        while let range = content.range(of: heading, range: search) {
            let atLineStart = range.lowerBound == content.startIndex
                || content[content.index(before: range.lowerBound)] == "\n"
            let rest = content[range.upperBound...].prefix { $0 != "\n" }
            if atLineStart && rest.allSatisfy(\.isWhitespace) {
                return range.lowerBound..<content.index(range.upperBound, offsetBy: rest.count)
            }
            search = range.upperBound..<content.endIndex
        }
        return nil
    }

    nonisolated private static func trimmingTrailingNewlines(_ text: String) -> String {
        var trimmed = text
        while trimmed.hasSuffix("\n") { trimmed.removeLast() }
        return trimmed
    }

    /// Index of the first line of the trailing tag-only block (Bear keeps
    /// `#project`-style tags as the last line(s) of a note), or nil.
    nonisolated private static func trailingTagBlockStart(of content: String) -> String.Index? {
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
}
