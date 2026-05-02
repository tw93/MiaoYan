import Foundation

@MainActor
final class WikilinkIndex: ObservableObject {
    static let shared = WikilinkIndex()

    private var outlinks: [String: Set<String>] = [:]
    private var inlinks: [String: Set<String>] = [:]

    private init() {}

    func rebuild(notes: [Note]) {
        outlinks.removeAll()
        inlinks.removeAll()

        for note in notes {
            let title = note.title
            let links = extractWikilinks(from: note.content.string)

            outlinks[title] = links

            for target in links {
                inlinks[target, default: []].insert(title)
            }
        }
    }

    func getBacklinks(for noteTitle: String) -> [String] {
        Array(inlinks[noteTitle] ?? []).sorted()
    }

    func getOutlinks(for noteTitle: String) -> [String] {
        Array(outlinks[noteTitle] ?? []).sorted()
    }

    private static let wikilinkRegex: NSRegularExpression? = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)

    private func extractWikilinks(from text: String) -> Set<String> {
        guard let regex = Self.wikilinkRegex else {
            return []
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var links = Set<String>()

        for match in matches {
            if let range = Range(match.range(at: 1), in: text) {
                let link = String(text[range]).trimmingCharacters(in: .whitespaces)
                links.insert(link)
            }
        }

        return links
    }

    func updateNote(title: String, content: String) {
        let links = extractWikilinks(from: content)

        if let oldLinks = outlinks[title] {
            for oldTarget in oldLinks where !links.contains(oldTarget) {
                inlinks[oldTarget]?.remove(title)
            }
        }

        outlinks[title] = links

        for target in links {
            inlinks[target, default: []].insert(title)
        }
    }

    func removeNote(title: String) {
        if let links = outlinks[title] {
            for target in links {
                inlinks[target]?.remove(title)
            }
        }
        outlinks.removeValue(forKey: title)
        inlinks.removeValue(forKey: title)
    }
}
