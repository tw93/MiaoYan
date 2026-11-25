import Cocoa
import Foundation
import MiaoYanCore

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
                    FileManager.default.fileExists(atPath: localNotePath)
                {
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
            let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        {
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

    /// `reserved` holds paths already promised to a copy still under way,
    /// which are as taken as a file on disk.
    public static func getFileName(from: URL? = nil, to: URL, ext: String? = nil, reserved: Set<String> = []) -> String? {
        let path = from?.absoluteString ?? to.absoluteString
        var name: String?

        if path.starts(with: "http://") || path.starts(with: "https://"),
            let webName = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        {
            name = webName
        }

        if path.starts(with: "file://") {
            var ext = ext ?? "jpg"
            var pathComponent = NSUUID().uuidString.lowercased() + "." + ext

            if let from = from {
                pathComponent = AttachmentFile.normalizedName(from.lastPathComponent, fallbackExtension: ext)
                ext = from.pathExtension
            }

            while name == nil {
                let destination = to.appendingPathComponent(pathComponent)
                // iCloud keeps a file not downloaded yet as `.name.icloud`
                // beside it; taking its name would overwrite it on arrival.
                let icloud = to.appendingPathComponent(".\(pathComponent).icloud")

                if reserved.contains(destination.path) || FileManager.default.fileExists(atPath: destination.path)
                    || FileManager.default.fileExists(atPath: icloud.path)
                {
                    pathComponent = NSUUID().uuidString.lowercased() + (ext.isEmpty ? "" : ".\(ext)")
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
        let prefix = NotesTextProcessor.getAttachPrefix(url: url)

        let project = note.project
        let destination = URL(fileURLWithPath: project.url.path + prefix)

        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false, attributes: nil)
        } catch {}

        guard let fileName = ImagesProcessor.getFileName(from: url, to: destination, ext: ext, reserved: reservedAttachments) else { return nil }

        let to = destination.appendingPathComponent(fileName)
        // No file, no link: a link to a file that was never written showed
        // a broken image where the paste or drop seemed to have worked.
        do {
            try data.write(to: to, options: .atomic)
        } catch {
            AppDelegate.trackError(error, context: "ImagesProcessor.writeFile")
            return nil
        }

        return "\(prefix)\(fileName)"
    }

    /// Destinations named for a copy that has not finished yet.
    @MainActor private static var reservedAttachments = Set<String>()

    /// Takes the name `url` gets in its note's folder for its kind (the same
    /// name dedupe and `.icloud` check `writeFile` uses) and holds it until
    /// `finishCopy`, so two files dropped with one name while the
    /// first is still copying do not get the same one. Returns the link path
    /// (`/files/Report-v2.pdf`) and where the file goes.
    @MainActor
    static func reserveAttachment(for url: URL, note: Note) -> (path: String, destination: URL)? {
        let prefix = NotesTextProcessor.getAttachPrefix(url: url)
        let folder = URL(fileURLWithPath: note.project.url.path + prefix)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: nil)
        guard let fileName = getFileName(from: url, to: folder, ext: url.pathExtension, reserved: reservedAttachments) else { return nil }
        let destination = folder.appendingPathComponent(fileName)
        reservedAttachments.insert(destination.path)
        return ("\(prefix)\(fileName)", destination)
    }

    /// Where a copy still under way goes once it lands, when the note that
    /// links it moved meanwhile (`forwardCopy`), by the path it is headed for.
    @MainActor private static var forwardedAttachments: [String: URL] = [:]

    /// The note linking a copy still under way at `url` moved into `folder`:
    /// a name is taken there now (the same name when it is free), and the
    /// copy is moved on to it once it lands (`finishCopy`). Moving the note
    /// found no file to carry yet, so the copy landed in the old folder and
    /// the moved note's link pointed nowhere. Nil when `url` is no copy
    /// under way or no name can be had.
    @MainActor
    static func forwardCopy(at url: URL, into folder: URL) -> URL? {
        let path = url.standardizedFileURL.path
        guard let key = reservedAttachments.first(where: { URL(fileURLWithPath: $0).standardizedFileURL.path == path }),
            forwardedAttachments[key] == nil
        else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        guard let fileName = getFileName(from: url, to: folder, ext: url.pathExtension, reserved: reservedAttachments) else { return nil }
        let target = folder.appendingPathComponent(fileName)
        reservedAttachments.insert(target.path)
        forwardedAttachments[key] = target
        return target
    }

    /// A copy to `destination` ended, `copied` or not: its name is free
    /// again, and a landed file is moved on along every `forwardCopy` its
    /// note's moves made. Returns where the file is.
    @MainActor
    @discardableResult
    static func finishCopy(_ destination: URL, copied: Bool) -> URL {
        reservedAttachments.remove(destination.path)
        var landed = destination
        var movable = copied
        var key = destination.path
        while let next = forwardedAttachments.removeValue(forKey: key) {
            reservedAttachments.remove(next.path)
            key = next.path
            guard movable else { continue }
            do {
                try FileManager.default.moveItem(at: landed, to: next)
                landed = next
            } catch {
                AppDelegate.trackError(error, context: "ImagesProcessor.finishCopy")
                movable = false
            }
        }
        if reservedAttachments.isEmpty {
            let waiters = copyWaiters.values
            copyWaiters.removeAll()
            for waiter in waiters { waiter() }
        }
        return landed
    }

    /// Callers waiting for every copy to end, by a key of their own.
    @MainActor private static var copyWaiters: [UUID: () -> Void] = [:]

    /// Calls `completion` once no copy is under way, or once `cap` seconds
    /// have passed, whichever comes first; false, and nothing is called, when
    /// none is under way. Quitting waits here: cut short, a copy left the
    /// note's link with no file and a `.<UUID>.partial` beside it.
    @MainActor
    static func deferUntilCopiesFinish(cap: TimeInterval, _ completion: @escaping () -> Void) -> Bool {
        guard !reservedAttachments.isEmpty else { return false }
        let key = UUID()
        copyWaiters[key] = completion
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(cap, 0) * 1_000_000_000))
            copyWaiters.removeValue(forKey: key)?()
        }
        return true
    }

    /// The folders a copy is being written into now, resolved, so Clean
    /// Unused Attachments leaves their partial copies alone.
    @MainActor
    static var foldersWithCopiesUnderWay: Set<String> {
        Set(reservedAttachments.map { URL(fileURLWithPath: $0).deletingLastPathComponent().resolvingSymlinksInPath().path })
    }

    /// The hidden name `copyAttachment` writes through, `.<UUID>.partial`,
    /// or `.<name>.<UUID>.partial` as builds before 2026-11-25 wrote it. One
    /// left by a crash or a forced quit is nobody's file.
    nonisolated static func isPartialCopyName(_ name: String) -> Bool {
        guard name.hasPrefix("."), name.hasSuffix(".partial") else { return false }
        let stem = name.dropLast(".partial".count)
        guard let last = stem.split(separator: ".").last else { return false }
        return UUID(uuidString: String(last)) != nil
    }

    #if DEBUG
        /// Runs on the thread each copy runs on, just before it copies, so a
        /// test can check that thread or hold the copy back. Set it only from
        /// a test, before the copy starts.
        nonisolated(unsafe) static var willCopyAttachment: (@Sendable (URL) -> Void)?
    #endif

    /// Clones `source` to `destination` without reading it into memory,
    /// through a hidden name beside it, so a copy cut short by a quit leaves
    /// no half-written file under the name the note links. The hidden name is
    /// `.<UUID>.partial` alone: with the file's name in it too, 46 characters
    /// longer, a name past about 209 characters failed as too long against
    /// APFS's 255 where writing the file itself worked. Fails rather than overwrite a file
    /// that appeared at `destination` meanwhile. Call it off the main thread.
    nonisolated static func copyAttachment(from source: URL, to destination: URL) throws {
        #if DEBUG
            willCopyAttachment?(destination)
        #endif
        let manager = FileManager.default
        let partial = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
        try manager.copyItem(at: source, to: partial)
        do {
            try manager.moveItem(at: partial, to: destination)
        } catch {
            try? manager.removeItem(at: partial)
            throw error
        }
    }
}
