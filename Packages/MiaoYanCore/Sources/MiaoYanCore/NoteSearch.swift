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
    /// Matching candidates in their original order with a priority. Every
    /// note whose title holds all the terms is kept, since those rank first
    /// and cost no file read; body matches then fill up to `limit`. Stopping
    /// at `limit` in list order used to drop an exact title match that sat
    /// after a hundred body matches. Runs off the main thread.
    public static func match(
        _ candidates: [NoteSearchCandidate],
        terms: [String],
        limit: Int,
        isCancelled: () -> Bool
    ) -> [(index: Int, priority: Int)] {
        guard !terms.isEmpty else { return candidates.map { ($0.index, 0) } }
        var matches: [(index: Int, priority: Int)] = []
        var titleMatched = Set<Int>()
        for candidate in candidates where terms.allSatisfy({ candidate.title.contains($0) }) {
            if isCancelled() { return [] }
            matches.append((candidate.index, 4))
            titleMatched.insert(candidate.index)
        }
        for candidate in candidates where !titleMatched.contains(candidate.index) {
            if matches.count >= limit { break }
            if isCancelled() { return [] }
            let body = {
                candidate.loadedText ?? (try? Data(contentsOf: candidate.url)).flatMap(NoteText.decode) ?? ""
            }
            guard let priority = priority(title: candidate.title, body: body, terms: terms) else { continue }
            matches.append((candidate.index, priority))
        }
        return matches.sorted { $0.index < $1.index }
    }

    /// 4 when every term is in the title, then 3, 2, 1 as more of the match
    /// comes from the body; nil when some term is in neither. `body` is only
    /// read when the title alone does not settle it.
    public static func priority(title: String, body: () -> String, terms: [String]) -> Int? {
        guard !terms.isEmpty else { return 0 }

        let titleMatches = terms.filter { title.contains($0) }.count
        if titleMatches == terms.count { return 4 }

        let content = searchable(body())
        var contentMatches = 0
        for term in terms where !title.contains(term) {
            guard bodyContains(content, term) else { return nil }
            contentMatches += 1
        }

        if titleMatches > contentMatches { return 3 }
        return titleMatches > 0 ? 2 : 1
    }

    /// The body in composed form, so a literal search still finds `café`
    /// whether it was stored precomposed or as `e` plus a combining accent.
    /// Text without combining marks, nearly every note, is used as it is.
    static func searchable(_ body: String) -> NSString {
        let text = body as NSString
        guard text.rangeOfCharacter(from: .nonBaseCharacters).location != NSNotFound else { return text }
        return body.precomposedStringWithCanonicalMapping as NSString
    }

    /// Case-insensitive and diacritic-sensitive, like the `lowercased()` and
    /// `contains` it replaces, without building a lowercased copy of every
    /// body for every query: on 3,000 notes that copy cost about 0.8s.
    static func bodyContains(_ content: NSString, _ term: String) -> Bool {
        content.range(of: term.precomposedStringWithCanonicalMapping, options: [.caseInsensitive, .literal]).location != NSNotFound
    }
}
