import Foundation

struct NoteFile: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let title: String
    let modifiedDate: Date
    let preview: String
    let isPinned: Bool

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        self.modifiedDate = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date.distantPast
        self.isPinned = url.lastPathComponent.hasPrefix("📌")
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            let lines = content.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("---") }
            self.preview = lines.prefix(2).joined(separator: " ")
        } else {
            self.preview = ""
        }
    }

    static func == (lhs: NoteFile, rhs: NoteFile) -> Bool {
        lhs.id == rhs.id
    }
}

struct FolderItem: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    let noteCount: Int
    let isTrash: Bool

    init(url: URL, name: String, noteCount: Int, isTrash: Bool = false) {
        self.id = UUID()
        self.url = url
        self.name = name
        self.noteCount = noteCount
        self.isTrash = isTrash
    }
}

enum FileReader {
    private static let allowedExtensions = Set(["md", "markdown", "txt"])

    static func folders(in root: URL) -> [FolderItem] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var result: [FolderItem] = []

        let allCount = countNotes(in: root, fm: fm)
        result.append(FolderItem(url: root, name: "All Notes", noteCount: allCount))

        let dirs = items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { $0.lastPathComponent != "Trash" && $0.lastPathComponent != ".Trash" }
            .sorted { $0.lastPathComponent.localizedCompare($1.lastPathComponent) == .orderedAscending }

        for dir in dirs {
            let count = countNotes(in: dir, fm: fm)
            result.append(FolderItem(url: dir, name: dir.lastPathComponent, noteCount: count))
        }

        let trashURL = root.appendingPathComponent("Trash")
        if fm.fileExists(atPath: trashURL.path) {
            let count = countNotes(in: trashURL, fm: fm)
            result.append(FolderItem(url: trashURL, name: "Trash", noteCount: count, isTrash: true))
        }

        return result
    }

    static func notes(in folder: URL) -> [NoteFile] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        var notes = items.compactMap { url -> NoteFile? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { return nil }
            guard allowedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            return NoteFile(url: url)
        }

        notes.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.modifiedDate > b.modifiedDate
        }
        return notes
    }

    static func readContent(of note: NoteFile) -> String {
        (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
    }

    static func search(query: String, in root: URL) -> [(NoteFile, String)] {
        guard !query.isEmpty else { return [] }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let lowQuery = query.lowercased()
        var results: [(NoteFile, String)] = []

        for case let url as URL in enumerator {
            guard allowedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let titleLower = url.deletingPathExtension().lastPathComponent.lowercased()
            if content.lowercased().contains(lowQuery) || titleLower.contains(lowQuery) {
                let note = NoteFile(url: url)
                let snippet = extractSnippet(from: content, query: lowQuery)
                results.append((note, snippet))
            }
        }

        results.sort { a, b in a.0.modifiedDate > b.0.modifiedDate }
        return results
    }

    private static func countNotes(in dir: URL, fm: FileManager) -> Int {
        (try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ))?.filter { allowedExtensions.contains($0.pathExtension.lowercased()) }.count ?? 0
    }

    private static func extractSnippet(from content: String, query: String) -> String {
        let lower = content.lowercased()
        guard let range = lower.range(of: query) else { return String(content.prefix(120)) }
        let startDist = content.distance(from: content.startIndex, to: range.lowerBound)
        let prefixStart = max(0, startDist - 40)
        let startIdx = content.index(content.startIndex, offsetBy: prefixStart)
        let endDist = min(content.count, startDist + query.count + 80)
        let endIdx = content.index(content.startIndex, offsetBy: endDist)
        let prefix = prefixStart > 0 ? "..." : ""
        let suffix = endDist < content.count ? "..." : ""
        return prefix + content[startIdx..<endIdx] + suffix
    }
}
