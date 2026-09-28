import Foundation

/// A note as the background matcher sees it: plain values only, so reading and
/// lowercasing bodies can leave the main thread without touching an app's
/// note model.
public struct NoteSearchCandidate: Sendable {
    public let index: Int
    /// Lowercased file name without the extension, so `.` or `md` no longer
    /// matches every note through `.md`.
    public let title: String
    public let url: URL
    /// The in-memory text of a loaded note, which can be newer than the file.
    /// Nil means read the file.
    public let loadedText: String?

    public init(index: Int, title: String, url: URL, loadedText: String?) {
        self.index = index
        self.title = title
        self.url = url
        self.loadedText = loadedText
    }
}

public enum NoteContentMatcher {
    /// Matching candidates in their original order with a priority, stopping
    /// after `limit`. Runs off the main thread.
    public static func match(
        _ candidates: [NoteSearchCandidate],
        terms: [String],
        limit: Int,
        isCancelled: () -> Bool
    ) -> [(index: Int, priority: Int)] {
        var matches: [(index: Int, priority: Int)] = []
        for candidate in candidates {
            if isCancelled() { return [] }
            let body = {
                candidate.loadedText ?? (try? String(contentsOf: candidate.url, encoding: .utf8)) ?? ""
            }
            guard let priority = priority(title: candidate.title, body: body, terms: terms) else { continue }
            matches.append((candidate.index, priority))
            if matches.count >= limit { break }
        }
        return matches
    }

    /// 4 when every term is in the title, then 3, 2, 1 as more of the match
    /// comes from the body; nil when some term is in neither. `body` is only
    /// read when the title alone does not settle it.
    public static func priority(title: String, body: () -> String, terms: [String]) -> Int? {
        guard !terms.isEmpty else { return 0 }

        let titleMatches = terms.filter { title.contains($0) }.count
        if titleMatches == terms.count { return 4 }

        let content = body().lowercased()
        var contentMatches = 0
        for term in terms where !title.contains(term) {
            guard content.contains(term) else { return nil }
            contentMatches += 1
        }

        if titleMatches > contentMatches { return 3 }
        return titleMatches > 0 ? 2 : 1
    }
}
