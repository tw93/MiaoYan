import Cocoa
import Foundation

public class ImagesProcessor {
    typealias Size = NSSize
    typealias Image = NSImage
    typealias TView = EditTextView

    var styleApplier: NSMutableAttributedString
    var range: NSRange?
    var note: Note
    var paragraphRange: NSRange
    var textView: TView?

    var offset = 0
    var newLineOffset = 0

    init(styleApplier: NSMutableAttributedString, range: NSRange? = nil, note: Note, textView: TView? = nil) {
        self.styleApplier = styleApplier
        self.range = range
        self.note = note
        self.textView = textView

        if let unwrappedRange = range {
            paragraphRange = unwrappedRange
        } else {
            paragraphRange = NSRange(0..<styleApplier.length)
        }
    }

    @MainActor
    public func load() {
        var offset = 0

        // Create snapshots on MainActor to avoid cross-actor access in closures
        let currentNoteURLString = note.url.absoluteString
        let projectURL = note.project.url
        let cacheBaseURL = projectURL.appendingPathComponent("/.cache/")

        NotesTextProcessor.imageInlineRegex.matches(styleApplier.string, range: paragraphRange) { result in
            guard var range = result?.range else { return }

            range = NSRange(location: range.location - offset, length: range.length)
            let mdLink = self.styleApplier.attributedSubstring(from: range).string
            let title = self.getTitle(link: mdLink)

            if let font = UserDefaultsManagement.noteFont {
                self.styleApplier.addAttribute(.font, value: font, range: range)
            }

            NotesTextProcessor.imageOpeningSquareRegex.matches(self.styleApplier.string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                self.styleApplier.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }

            NotesTextProcessor.imageClosingSquareRegex.matches(self.styleApplier.string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                self.styleApplier.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }

            NotesTextProcessor.parenRegex.matches(self.styleApplier.string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }

                var url: URL?
                let filePath = self.getFilePath(innerRange: innerRange)

                if let localNotePath = self.getLocalNotePath(path: filePath, innerRange: innerRange),
                   FileManager.default.fileExists(atPath: localNotePath) {
                    url = URL(fileURLWithPath: localNotePath)
                } else if let fs = URL(string: filePath) {
                    url = fs
                }

                guard let imageUrl = url else { return }

                let invalidateRange = NSRange(location: range.location, length: 1)

                // Use snapshot to avoid cross-actor access to note.project in closure
                let cacheUrl = cacheBaseURL

                // Use snapshot comparison to avoid accessing EditTextView.note in closure
                if EditTextView.note?.url.absoluteString != currentNoteURLString {
                    return
                }

                let imageAttachment = NoteAttachment(
                    title: title,
                    path: filePath,
                    url: imageUrl,
                    cache: cacheUrl,
                    invalidateRange: invalidateRange,
                    note: self.note
                )

                if let attributedStringWithImage = imageAttachment.getAttributedString() {
                    offset += mdLink.count - 1
                    self.styleApplier.replaceCharacters(in: range, with: attributedStringWithImage)
                }
            }
        }
    }

    func computeMarkdownTitleLength(mdLink: String) -> Int {
        var mdTitleLength = 0
        if let match = mdLink.range(of: "\\[(.+)\\]", options: .regularExpression) {
            mdTitleLength = mdLink[match].count - 2
        }
        return mdTitleLength
    }

    private func getTitle(link: String) -> String {
        if let match = link.range(of: "\\[(.+)\\]", options: .regularExpression) {
            let title = link[match]
            return String(title.dropLast().dropFirst())
        }
        return ""
    }

    // Access note.project (@MainActor)
    @MainActor
    func getLocalNotePath(path: String, innerRange: NSRange) -> String? {
        let noteStorage = note.project
        var notePath: String
        let storagePath = noteStorage.url.path

        if path.starts(with: "/i/") || path.starts(with: "/files/") {
            let path = getFilePath(innerRange: innerRange)
            return note.project.url.path + path
        }

        if path.starts(with: "http://") || path.starts(with: "https://"),
           let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            notePath = storagePath + "/i/" + encodedPath
            return notePath
        }

        let path = getFilePath(innerRange: innerRange)
        notePath = storagePath + "/" + path

        return notePath
    }

    func getFilePath(innerRange: NSRange) -> String {
        let link = NSRange(location: innerRange.location + 1 + offset, length: innerRange.length - 2)
        if let path = styleApplier.attributedSubstring(from: link).string.removingPercentEncoding {
            return path
        }
        return ""
    }

    public static func getFileName(from: URL? = nil, to: URL, ext: String? = nil) -> String? {
        let path = from?.absoluteString ?? to.absoluteString
        var name: String?

        if path.starts(with: "http://") || path.starts(with: "https://"),
           let webName = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            name = webName
        }

        if path.starts(with: "file://") {
            var ext = ext ?? "jpg"
            var pathComponent = NSUUID().uuidString.lowercased() + "." + ext

            if let from = from {
                pathComponent = from.lastPathComponent
                ext = from.pathExtension
            }

            while name == nil {
                let destination = to.appendingPathComponent(pathComponent)
                let icloud = destination.appendingPathExtension("icloud")

                if FileManager.default.fileExists(atPath: destination.path) ||
                   FileManager.default.fileExists(atPath: icloud.path) {
                    pathComponent = NSUUID().uuidString.lowercased() + ".\(ext)"
                    continue
                }

                name = pathComponent
            }
        }

        return name
    }

    // Access note.project (@MainActor)
    @MainActor
    public static func writeFile(data: Data, url: URL? = nil, note: Note, ext: String? = nil) -> String? {
        var prefix = "/i/"
        if let url = url, !url.isImage {
            prefix = "/files/"
        }

        let project = note.project
        let destination = URL(fileURLWithPath: project.url.path + prefix)

        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false, attributes: nil)
        } catch {}

        guard let fileName = ImagesProcessor.getFileName(from: url, to: destination, ext: ext) else { return nil }

        let to = destination.appendingPathComponent(fileName)
        try? data.write(to: to, options: .atomic)

        return "\(prefix)\(fileName)"
    }

    func isContainAttachment(innerRange: NSRange, mdTitleLength: Int) -> Bool {
        let j = offset + newLineOffset - mdTitleLength
        if innerRange.lowerBound >= 5 + mdTitleLength {
            return styleApplier.containsAttachments(in: NSRange(location: innerRange.lowerBound - 5 + j, length: 1))
        }
        return false
    }

    func isContainNewLine(innerRange: NSRange, mdTitleLength: Int) -> Bool {
        let j = offset + newLineOffset - mdTitleLength
        if innerRange.lowerBound >= 4 + mdTitleLength {
            return (styleApplier.attributedSubstring(from: NSRange(location: innerRange.lowerBound - 4 + j, length: 1)).string == "\n")
        }
        return false
    }
}
