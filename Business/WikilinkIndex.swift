import Foundation
import MiaoYanCore

@MainActor
final class WikilinkIndex: ObservableObject {
    static let shared = WikilinkIndex()

    private var outlinks: [String: Set<String>] = [:]
    private var inlinks: [String: Set<String>] = [:]

    private init() {}

    private var rebuildTask: Task<Void, Never>?

    /// Backlinks cover every note, not only the listed ones, and most bodies
    /// are not loaded, so those are read from disk off the main thread.
    /// Saves keep the index current through updateNote afterwards.
    func rebuildFromAllNotes(in storage: Storage) {
        rebuildTask?.cancel()
        let notes = storage.noteList.filter { !$0.isTrash() }
        let titles = notes.map(\.title)
        let urls = notes.map(\.url)
        let loaded = notes.map { $0.isContentLoaded ? $0.content.string : nil }
        rebuildTask = Task {
            let texts = await Task.detached(priority: .utility) {
                zip(urls, loaded).map { url, text in text ?? (try? Data(contentsOf: url)).flatMap(NoteText.decode) ?? "" }
            }.value
            guard !Task.isCancelled else { return }
            rebuild(entries: Array(zip(titles, texts)))
        }
    }

    /// Titles with their text, for callers that read bodies from disk.
    func rebuild(entries: [(title: String, text: String)]) {
        outlinks.removeAll()
        inlinks.removeAll()

        for (title, text) in entries {
            let links = extractWikilinks(from: text)

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
