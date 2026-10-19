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
    /// Storage lists only the root's and first-level folders' notes until a
    /// deeper folder is opened, so the library roots are also walked on disk
    /// with the sidebar's folder rules. Saves keep the index current through
    /// updateNote afterwards.
    func rebuildFromAllNotes(in storage: Storage) {
        rebuildTask?.cancel()
        let notes = storage.noteList.filter { !$0.isTrash() }
        let listed = notes.map { ListedNote(title: $0.title, url: $0.url, text: $0.isContentLoaded ? $0.content.string : nil) }
        // A single opened file's folder can be anything (Downloads, home),
        // so only a library is walked.
        let roots = UserDefaultsManagement.isSingleMode ? [] : storage.getRootProjects().filter { !$0.isTrash }.map(\.url)
        let trashPaths = Set(storage.getProjects().filter(\.isTrash).map { $0.url.resolvingSymlinksInPath().path })
        let extensions = storage.allowedExtensions
        rebuildTask = Task {
            let reader = Task.detached(priority: .utility) {
                Self.readEntries(listed: listed, roots: roots, trashPaths: trashPaths, allowedExtensions: extensions)
            }
            // A newer rebuild cancels this one; the walk stops with it.
            let entries = await withTaskCancellationHandler {
                await reader.value
            } onCancel: {
                reader.cancel()
            }
            guard !Task.isCancelled else { return }
            rebuild(entries: entries)
        }
    }

    private struct ListedNote: Sendable {
        let title: String
        let url: URL
        let text: String?
    }

    /// Listed notes first (their loaded text wins), then every other note
    /// file under the roots. Stops adding files from disk past
    /// `maxWalkedNotes`, so a huge folder cannot keep the scan going for
    /// minutes; the listed notes are always included.
    nonisolated private static let maxWalkedNotes = 20_000

    nonisolated private static func readEntries(
        listed: [ListedNote], roots: [URL], trashPaths: Set<String>, allowedExtensions: [String]
    ) -> [(title: String, text: String)] {
        func read(_ url: URL) -> String {
            (try? Data(contentsOf: url)).flatMap(NoteText.decode) ?? ""
        }
        var entries: [(title: String, text: String)] = []
        var seen = Set<String>()
        for note in listed {
            seen.insert(note.url.resolvingSymlinksInPath().path)
            entries.append((note.title, note.text ?? read(note.url)))
        }
        let skipFolders: Set<String> = [".cache", "i", ".Trash", "files"]
        let keys: [URLResourceKey] = [.isDirectoryKey]
        var walked = 0
        for root in roots {
            guard
                let enumerator = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else { continue }
            for case let url as URL in enumerator {
                if Task.isCancelled || walked >= maxWalkedNotes { return entries }
                if (try? url.resourceValues(forKeys: Set(keys)))?.isDirectory == true {
                    if skipFolders.contains(url.lastPathComponent)
                        || trashPaths.contains(url.resolvingSymlinksInPath().path)
                        || Storage.isHiddenAssetsFolder(url, allowedExtensions: allowedExtensions)
                    {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard allowedExtensions.contains(url.pathExtension.lowercased()),
                    seen.insert(url.resolvingSymlinksInPath().path).inserted
                else { continue }
                walked += 1
                let title = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: ":", with: "/")
                entries.append((title, read(url)))
            }
        }
        return entries
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
