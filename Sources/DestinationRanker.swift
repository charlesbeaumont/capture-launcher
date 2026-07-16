import Foundation

struct RankedDestination: Identifiable, Sendable {
    let destination: Destination
    let score: Double
    var id: String { destination.id }
}

/// Pure per-keystroke ranking over the precomputed index. ~30 items,
/// no allocation-heavy work — comfortably sub-millisecond.
enum DestinationRanker {
    /// `pinned` is the empty-query default (Inbox for capture, the
    /// general-reference note for triage) and always occupies row 0
    /// when the query is empty.
    static func rank(
        indexed: [IndexedDestination],
        query: String,
        usageIndex: [String: Int],
        pinned: Destination?,
        now: Date = Date()
    ) -> [RankedDestination] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            var top: [RankedDestination] = []
            top.reserveCapacity(indexed.count)
            for item in indexed where !item.destination.paused {
                let score = recencyScore(item.destination, now: now)
                    + mruScore(item.destination, usageIndex)
                top.append(RankedDestination(destination: item.destination, score: score))
            }
            top.sort { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
            if let pinned {
                top.insert(RankedDestination(destination: pinned, score: .infinity), at: 0)
            }
            return top
        }

        let q = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var results: [RankedDestination] = []

        if let pinned {
            let pinnedIndexed = IndexedDestination(pinned)
            if let quality = matchQuality(pinnedIndexed, query: q) {
                results.append(RankedDestination(destination: pinned, score: quality + 5))
            }
        }
        for item in indexed {
            guard let quality = matchQuality(item, query: q) else { continue }
            let score = quality
                + recencyScore(item.destination, now: now)
                + mruScore(item.destination, usageIndex)
            results.append(RankedDestination(destination: item.destination, score: score))
        }
        return results.sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
    }

    // MARK: - Scoring

    /// leaf-prefix 100 > word-boundary prefix 80 > fuzzy subsequence 40 + compactness.
    static func matchQuality(_ item: IndexedDestination, query: String) -> Double? {
        if item.normalizedLeaf.hasPrefix(query) { return 100 }
        if item.words.contains(where: { $0.hasPrefix(query) }) { return 80 }
        if let span = subsequenceSpan(of: query, in: item.normalizedFull) {
            return 40 + 10 * (Double(query.count) / Double(span))
        }
        return nil
    }

    static func recencyScore(_ destination: Destination, now: Date) -> Double {
        guard let modified = destination.lastModified else { return 0 }
        let ageDays = max(0, now.timeIntervalSince(modified) / 86_400)
        return 20 * exp(-ageDays / 14)
    }

    static func mruScore(_ destination: Destination, _ usageIndex: [String: Int]) -> Double {
        guard let index = usageIndex[destination.tag] else { return 0 }
        return 15 * exp(-Double(index) / 5)
    }

    /// Greedy subsequence match; returns the span length (last matched index −
    /// first matched index + 1) or nil when `query` is not a subsequence.
    static func subsequenceSpan(of query: String, in text: String) -> Int? {
        guard !query.isEmpty else { return nil }
        var first: Int?
        var last = 0
        var queryIterator = query.makeIterator()
        var needle = queryIterator.next()
        for (offset, char) in text.enumerated() {
            guard let current = needle else { break }
            if char == current {
                if first == nil { first = offset }
                last = offset
                needle = queryIterator.next()
            }
        }
        guard needle == nil, let first else { return nil }
        return last - first + 1
    }
}
