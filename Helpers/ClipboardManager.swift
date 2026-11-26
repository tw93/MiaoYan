import Cocoa
import Darwin
import MiaoYanCore
import UniformTypeIdentifiers

private let uploadServerURL = "http://127.0.0.1:36677/upload"

@MainActor
class ClipboardManager {
    private weak var textView: EditTextView?

    init(textView: EditTextView) {
        self.textView = textView
    }

    func handleCopy() -> Bool {
        guard let textView = textView else { return false }

        if textView.selectedRanges.count > 1 {
            // Option-drag column selections: one line per selected range.
            let text = textView.string as NSString
            let combined = textView.selectedRanges
                .map(\.rangeValue)
                .filter { $0.length > 0 && NSMaxRange($0) <= text.length }
                .map { text.substring(with: $0) }
                .joined(separator: "\n")
            // Empty carets copy nothing rather than clearing the clipboard,
            // and leading indentation of the first range is part of the copy.
            guard !combined.isEmpty else { return true }
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(combined.removeLastNewLine(), forType: NSPasteboard.PasteboardType.string)
            return true
        }

        // A heading copied on its own is wanted as its words, without the
        // `#` marks (maintainer, 2026-11-16); a copy that runs past the line
        // keeps the Markdown as written. Cut is untouched, so a heading
        // moved by cut and paste stays a heading.
        if let title = loneHeadingTitle(in: textView) {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(title, forType: NSPasteboard.PasteboardType.string)
            return true
        }

        if textView.selectedRange.length == 0,
            let paragraphRange = textView.getParagraphRange(),
            let paragraph = textView.attributedSubstring(forProposedRange: paragraphRange, actualRange: nil)
        {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(paragraph.string.trim().removeLastNewLine(), forType: NSPasteboard.PasteboardType.string)
            return true
        }

        return false
    }

    /// The heading's words when the copy is exactly one heading line: the
    /// caret resting on it, or a selection from the line's start that stays
    /// on it. A `#` line inside a fenced code block is a comment, not a
    /// heading, and copies as written.
    private func loneHeadingTitle(in textView: EditTextView) -> String? {
        guard let storage = textView.textStorage else { return nil }
        let selection = textView.selectedRange()
        let text = storage.string as NSString
        guard NSMaxRange(selection) <= text.length else { return nil }
        let paragraph = text.paragraphRange(for: NSRange(location: selection.location, length: 0))
        let copied = selection.length == 0 ? paragraph : selection
        guard copied.location == paragraph.location, NSMaxRange(copied) <= NSMaxRange(paragraph),
            let title = Self.headingTitle(ofLine: text.substring(with: copied)),
            !NotesTextProcessor.fencedCodeBlockRanges(in: storage).contains(where: { NSIntersectionRange($0, paragraph).length > 0 })
        else { return nil }
        return title
    }

    /// `Title` for `## Title`, with or without the line's own line break and
    /// a closing run of `#`; nil for anything that is not one ATX heading.
    nonisolated static func headingTitle(ofLine line: String) -> String? {
        var line = line
        if line.last?.isNewline == true { line.removeLast() }
        guard !line.contains(where: \.isNewline),
            let regex = try? NSRegularExpression(pattern: "^ {0,3}#{1,6}[ \\t]+(.*?)(?:[ \\t]+#+)?[ \\t]*$"),
            let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        else { return nil }
        let title = (line as NSString).substring(with: match.range(at: 1))
        return title.isEmpty ? nil : title
    }

    /// Pasted HTML becomes Markdown, whose `<pre>` is a fenced block; inside a
    /// fence that would nest a second fence in the first, so plain text goes in.
    nonisolated static func shouldConvertHtml(caret: Int, in text: NSString) -> Bool {
        !ListContinuation.isInFencedCode(at: caret, in: text)
    }

    func handlePaste(in note: Note) -> Bool {
        guard let textView = textView else { return false }

        let pasteboard = NSPasteboard.general
        if pasteboard.string(forType: NSPasteboard.PasteboardType.fileURL) == nil {
            // Rich text copied from a browser (AI answers, docs pages) arrives as
            // HTML; convert to markdown when it carries block structure. Editor
            // syntax-highlight HTML has no such tags, so code paste stays plain.
            var content = pasteboard.string(forType: NSPasteboard.PasteboardType.string)
            if Self.shouldConvertHtml(caret: textView.selectedRange().location, in: textView.string as NSString),
                let html = pasteboard.string(forType: NSPasteboard.PasteboardType.html),
                let markdown = HtmlToMarkdown.convertIfStructured(html)
            {
                content = markdown
            }

            if let content = content {
                EditTextView.shouldForceRescan = true
                let currentRange = textView.selectedRange()
                textView.breakUndoCoalescing()
                textView.insertText(content, replacementRange: currentRange)
                textView.saveTextStorageContent(to: note)
                note.save()
                textView.fillHighlightLinks()
                return true
            }
        }

        return pasteImageFromClipboard(in: note)
    }

    private func pasteImageFromClipboard(in note: Note) -> Bool {
        guard let textView = textView else { return false }

        if let url = NSURL(from: NSPasteboard.general) {
            if !url.isFileURL {
                return false
            }
            return saveFile(url: url as URL, in: note)
        }

        if let clipboard = NSPasteboard.general.data(forType: .tiff),
            let image = NSImage(data: clipboard),
            let jpgData = image.jpgData
        {

            EditTextView.shouldForceRescan = true
            saveClipboard(data: jpgData, note: note)
            textView.saveTextStorageContent(to: note)
            note.save()
            textView.textStorage?.sizeAttachmentImages()
            return true
        }

        return false
    }

    /// Files dropped on the editor take the paste path: each is copied into
    /// the note's attachment folder (or uploaded, per the image upload
    /// setting) and its Markdown link goes in on a line of its own after the
    /// line of the drop point (`beginDroppedLine`). Left to
    /// NSTextView, which imports graphics, a file became an inline attachment
    /// that was never written anywhere, since a73f4585 removed the drop
    /// handling. Nil when the pasteboard holds no file, leaving the drop to
    /// NSTextView; false when the editor cannot take it (read-only, or the
    /// buffer is not the open note's, #543). A note of the library, which the
    /// shell's list drags as its file URL, is not an attachment: copied into
    /// `files/` it became a second copy of the note, so it is left out, and a
    /// drop of notes alone is refused.
    func dropFiles(
        from pasteboard: NSPasteboard, at location: Int, storage library: Storage = AppEnvironment.current.storage
    ) -> Bool? {
        let dropped = Self.fileURLs(on: pasteboard)
        guard !dropped.isEmpty else { return dropPromisesOrImage(from: pasteboard, at: location) }
        let urls = dropped.filter { library.getBy(url: $0) == nil }
        guard !urls.isEmpty, let textView, textView.isEditable, let note = EditTextView.note, textView.storageNote === note,
            let storage = textView.textStorage
        else { return false }
        textView.undoManager?.beginUndoGrouping()
        let lineBreak = beginDroppedLine(at: location, in: textView, storage: storage)
        let length = storage.length
        var inserted = 0
        for url in urls {
            if inserted > 0 {
                textView.insertText("\n\n", replacementRange: textView.selectedRange())
            }
            droppedLineBreak = inserted == 0 ? lineBreak.map { storage.mutableString.substring(with: $0) } : nil
            if saveFile(url: url, in: note) {
                inserted += 1
            }
        }
        endDroppedLine(lineBreak, inserted: storage.length != length, in: textView)
        textView.undoManager?.endUndoGrouping()
        return inserted > 0
    }

    /// A drop goes after the line it was let go on, on a line of its own,
    /// and never splits that line (maintainer 2026-11-26): the caret moves to
    /// the line's end, or the end of the table or fenced code block the drop
    /// landed in (`DropPlacement`), and a line holding text gets a line
    /// break first. The
    /// iPhone and iPad editor places a dropped picture the same way. Returns
    /// the break, for a drop that put nothing in to take back; that is read
    /// from the text's length, since `saveFile` answers true for a picture
    /// whose file could not be written.
    private func beginDroppedLine(at location: Int, in textView: EditTextView, storage: NSTextStorage) -> NSRange? {
        let text = storage.string as NSString
        let end = DropPlacement.lineEnd(around: location, in: text)
        textView.setSelectedRange(NSRange(location: end, length: 0))
        guard end > 0 else { return nil }
        let previous = text.character(at: end - 1)
        guard previous != 0x0A, previous != 0x0D else { return nil }
        // A note written with CRLF keeps one kind of line ending. Coalescing
        // is broken first, as before every insert in this file, so the break
        // belongs to the drop's undo group rather than the typing before it.
        let lineBreak = ListContinuation.lineBreak(in: text)
        textView.breakUndoCoalescing()
        textView.insertText(lineBreak, replacementRange: NSRange(location: end, length: 0))
        return NSRange(location: end, length: (lineBreak as NSString).length)
    }

    private func endDroppedLine(_ lineBreak: NSRange?, inserted: Bool, in textView: EditTextView) {
        droppedLineBreak = nil
        guard !inserted, let lineBreak else { return }
        textView.insertText("", replacementRange: lineBreak)
    }

    /// The line break `beginDroppedLine` put in front of the link about to
    /// go in, while no link of the drop has, so a copy that fails later
    /// takes the break out with its link (`copyFile`).
    private var droppedLineBreak: String?

    /// A drag that carries no readable file: the files its source promises
    /// to write, as Photos, Mail and browsers offer a picture, or else bare
    /// picture data with no text beside it (#578). Left to NSTextView, a
    /// promise was not accepted at all, so dragging a photo in did nothing,
    /// and picture data became an inline attachment that was never written
    /// anywhere. Promised files arrive later and go in where the drop was,
    /// through `saveFile` like a Finder file. Nil when the drag has neither,
    /// leaving it to NSTextView; false when the editor cannot take it.
    private func dropPromisesOrImage(from pasteboard: NSPasteboard, at location: Int) -> Bool? {
        let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
        let image = promises.isEmpty ? Self.imageData(on: pasteboard) : nil
        guard !promises.isEmpty || image != nil else { return nil }
        guard let textView, textView.isEditable, let note = EditTextView.note, textView.storageNote === note,
            let storage = textView.textStorage
        else { return false }
        let caret = min(max(location, 0), storage.length)
        guard let image else {
            receive(promises, into: note, at: caret)
            return true
        }
        textView.undoManager?.beginUndoGrouping()
        let lineBreak = beginDroppedLine(at: caret, in: textView, storage: storage)
        let length = storage.length
        EditTextView.shouldForceRescan = true
        saveClipboard(data: image.data, note: note, ext: image.ext)
        endDroppedLine(lineBreak, inserted: storage.length != length, in: textView)
        textView.undoManager?.endUndoGrouping()
        textView.saveTextStorageContent(to: note)
        note.save()
        return true
    }

    /// Picture data on a pasteboard that holds no text, PNG kept as PNG and
    /// anything else NSImage reads saved as JPEG, as a pasted picture is. A
    /// text selection dragged from a page can carry its pictures too; it
    /// stays text.
    static func imageData(on pasteboard: NSPasteboard) -> (data: Data, ext: String)? {
        let types = pasteboard.types ?? []
        guard !types.contains(where: { [.string, .html, .rtf, .rtfd].contains($0) }) else { return nil }
        if let png = pasteboard.data(forType: .png), NSImage(data: png) != nil { return (png, "png") }
        for type in [NSPasteboard.PasteboardType(UTType.jpeg.identifier), .tiff] {
            if let data = pasteboard.data(forType: type), let jpg = NSImage(data: data)?.jpgData { return (jpg, "jpg") }
        }
        return nil
    }

    /// Asks each source to write its file into a folder of its own, then
    /// inserts the files in the order they were dragged, once all have
    /// arrived, if the editor still shows the note they were dropped on.
    private func receive(_ promises: [NSFilePromiseReceiver], into note: Note, at caret: Int) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoYanDrop-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            AppDelegate.trackError(error, context: "ClipboardManager.receivePromises")
            return
        }
        let arrivals = PromiseArrivals(count: promises.count) { [weak self] files in
            self?.insertReceived(files, into: note, at: caret)
            // A received file that is not an image is still being copied
            // out of the folder; it goes once those copies are done.
            let copies = self?.copies ?? []
            Task {
                for copy in copies { await copy.value }
                try? FileManager.default.removeItem(at: folder)
            }
        }
        for (index, promise) in promises.enumerated() {
            promise.receivePromisedFiles(
                atDestination: folder, options: [:], operationQueue: Self.promiseQueue,
                reader: PromiseArrivals.reader(for: arrivals, at: index))
        }
    }

    private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private func insertReceived(_ files: [URL], into note: Note, at caret: Int) {
        guard !files.isEmpty, let textView, textView.isEditable, EditTextView.note === note, textView.storageNote === note,
            let storage = textView.textStorage
        else { return }
        textView.undoManager?.beginUndoGrouping()
        let lineBreak = beginDroppedLine(at: caret, in: textView, storage: storage)
        let length = storage.length
        var inserted = 0
        for url in files {
            if inserted > 0 {
                textView.insertText("\n\n", replacementRange: textView.selectedRange())
            }
            droppedLineBreak = inserted == 0 ? lineBreak.map { storage.mutableString.substring(with: $0) } : nil
            if saveFile(url: url, in: note) {
                inserted += 1
            }
        }
        endDroppedLine(lineBreak, inserted: storage.length != length, in: textView)
        textView.undoManager?.endUndoGrouping()
    }

    /// The regular files on a pasteboard, as Finder puts them there when
    /// files are dragged; folders and web links are not among them.
    static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
        return objects.compactMap { $0 as? URL }.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && FileManager.default.isReadableFile(atPath: $0.path)
        }
    }

    /// Puts the file at `url` into the note at the caret. An image is read,
    /// written to `i/` and linked as before (and may go to the image host);
    /// a video or any other file is linked at once and cloned into `files/`
    /// off the main thread (`copyFile`).
    func saveFile(url: URL, in note: Note) -> Bool {
        guard let textView = textView else { return false }

        let kind = AttachmentFile.kind(ofExtension: url.pathExtension)
        guard kind == .image else { return copyFile(url: url, kind: kind, in: note) }

        if let data = try? Data(contentsOf: url) {
            var ext: String?

            if NSImage(data: data) != nil {
                ext = "jpg"
                if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                    let uti = CGImageSourceGetType(source)
                    if let fileExtension = (uti as String?)?.utiFileExtension {
                        ext = fileExtension
                    }
                }
            }

            EditTextView.shouldForceRescan = true
            saveClipboard(data: data, note: note, ext: ext, url: url)
            textView.saveTextStorageContent(to: note)
            note.save()
            textView.textStorage?.sizeAttachmentImages()
            return true
        }

        return false
    }

    /// The copies `copyFile` started, newest last, so a caller (the promise
    /// folder's clean-up, a test) can wait for them.
    private(set) var copies: [Task<Void, Never>] = []

    /// A video or any other file was read whole into memory and written back
    /// on the main thread, so dropping a large video or PDF stalled the
    /// editor. Its name in `files/` is taken now and its link goes in at the
    /// caret, in order with whatever else is put in alongside it; the file is
    /// cloned there off the main thread (`FileManager.copyItem`, an APFS clone
    /// on the same volume). If the copy fails the link is taken out again, so
    /// no link is left pointing at a file that was never written.
    private func copyFile(url: URL, kind: AttachmentFile.Kind, in note: Note) -> Bool {
        guard let textView, let reserved = ImagesProcessor.reserveAttachment(for: url, note: note) else { return false }
        let link = AttachmentFile.markdown(path: reserved.path, kind: kind, title: url.lastPathComponent)
        let removal = (droppedLineBreak ?? "") + link
        droppedLineBreak = nil
        EditTextView.shouldForceRescan = true
        textView.breakUndoCoalescing()
        textView.insertText(link, replacementRange: textView.selectedRange())
        textView.saveTextStorageContent(to: note)
        note.save()

        let destination = reserved.destination
        copies.append(
            Task { [weak textView] in
                let failure = await Task.detached(priority: .userInitiated) { () -> Error? in
                    do {
                        try ImagesProcessor.copyAttachment(from: url, to: destination)
                        return nil
                    } catch {
                        return error
                    }
                }.value
                ImagesProcessor.releaseAttachment(destination)
                guard let failure else { return }
                AppDelegate.trackError(failure, context: "ClipboardManager.copyFile")
                if !Self.removeLink(removal, of: note, in: textView), removal != link {
                    Self.removeLink(link, of: note, in: textView)
                }
                textView?.window?.contentViewController?.toast(message: I18n.str("Save Failed"), style: .failure)
            })
        return true
    }

    /// Takes the link of a file that could not be copied back out of the
    /// note: from the editor while it still holds that note, else from the
    /// note's own text. False when the text no longer holds it.
    @discardableResult
    private static func removeLink(_ link: String, of note: Note, in textView: EditTextView?) -> Bool {
        if let textView, textView.storageNote === note, let storage = textView.textStorage {
            let range = storage.mutableString.range(of: link)
            if range.location != NSNotFound {
                if textView.shouldChangeText(in: range, replacementString: "") {
                    storage.replaceCharacters(in: range, with: "")
                    textView.didChangeText()
                } else {
                    storage.replaceCharacters(in: range, with: "")
                }
                textView.saveTextStorageContent(to: note)
                note.save()
                return true
            }
        }
        let range = note.content.mutableString.range(of: link)
        guard range.location != NSNotFound else { return false }
        note.content.replaceCharacters(in: range, with: "")
        note.save()
        return true
    }

    // Simplified parameters for uPic/Picsee
    struct UploadParameters {
        let localPath: String
        let originalPath: String
        let picType: String
        let textView: EditTextView
        let note: Note
        let placeholder: String
    }

    /// Placeholder inserted while an upload is in flight. Must be unique per
    /// upload: a shared literal made concurrent uploads (or a stale
    /// placeholder saved in another note) match the wrong buffer, and the
    /// follow-up whole-buffer save then wrote note X's text into note Y (#543).
    static func makeUploadPlaceholder() -> String {
        "![](uploading-\(UUID().uuidString.prefix(8))...)"
    }

    private func saveClipboard(data: Data, note: Note, ext: String? = nil, url: URL? = nil) {
        // Toasts go to whatever controller hosts the editor: the SwiftUI
        // shell has no ViewController, and requiring one made every image
        // paste there a silent no-op that still swallowed the paste.
        guard let textView = textView else { return }
        let host = textView.window?.contentViewController

        if let path = ImagesProcessor.writeFile(data: data, url: url, note: note, ext: ext) {
            // A video or an image is drawn in place; any other file is a
            // link named as it was dropped, the Markdown the iPhone writes.
            let kind = url.map { AttachmentFile.kind(ofExtension: $0.pathExtension) } ?? .image
            let defaultImage = NSAttributedString(
                string: AttachmentFile.markdown(path: path, kind: path.hasPrefix("/i/") ? .image : kind, title: url?.lastPathComponent ?? ""))
            let imagePath = "\(note.project.url.path)\(path)"
            let tempPath = URL(fileURLWithPath: imagePath)

            switch Self.uploadHost(forAttachmentAt: path, setting: UserDefaultsManagement.defaultPicUpload) {
            case .http:
                host?.toast(message: I18n.str("Uploading image…"))
                // The local link holds the spot until the upload finishes:
                // inserting the link at the cursor afterwards dropped it wherever
                // the cursor had moved. The file name is unique, and a quit or a
                // failed upload leaves a working local image instead of a
                // placeholder that also orphaned the file.
                let placeholderText = defaultImage.string
                textView.breakUndoCoalescing()
                textView.insertText(defaultImage, replacementRange: textView.selectedRange())

                postToPicGo(imagePath: imagePath, serverURL: uploadServerURL) { [weak self] result, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let resultString = result {
                            // The local link is a working image, so the file goes
                            // only once the note points at the cloud copy: a link
                            // edited during the upload (alt text added) is missed
                            // by the swap and would otherwise be left broken.
                            if self.replacePlaceholderWithURL(placeholder: placeholderText, cloudURL: resultString, textView: textView, note: note) {
                                self.deleteImage(tempPath: tempPath)
                            }
                        } else {
                            if let error {
                                AppDelegate.trackError(error, context: "ClipboardManager.uploadToCloudAsync")
                            }
                            textView.window?.contentViewController?.toast(message: I18n.str("Upload failed. The local image was kept"), style: .failure)
                        }
                    }
                }
            case .app(let picType):
                // Restore uPic/Picsee support via Shell Command
                let placeholderText = Self.makeUploadPlaceholder()
                let uploadingPlaceholder = NSAttributedString(string: placeholderText)
                textView.breakUndoCoalescing()
                textView.insertText(uploadingPlaceholder, replacementRange: textView.selectedRange())

                let uploadParams = UploadParameters(
                    localPath: tempPath.path,
                    originalPath: path,
                    picType: picType,
                    textView: textView,
                    note: note,
                    placeholder: placeholderText
                )
                uploadToCloudAsync(parameters: uploadParams)
            case nil:
                // Default local storage
                textView.breakUndoCoalescing()
                textView.insertText(defaultImage, replacementRange: textView.selectedRange())
            }
        }
    }

    enum UploadHost: Equatable {
        /// PicGo or PicList, over their local HTTP endpoint.
        case http
        /// uPic or Picsee, run as a command.
        case app(String)
    }

    /// The image host that takes the attachment just written at `path`
    /// (`/i/shot.png`), if the setting names one. Only images go up: a PDF
    /// or a video went to the host as well, came back as `![](https://….pdf)`
    /// and its local file was trashed; anything outside `i/` stays local.
    static func uploadHost(forAttachmentAt path: String, setting: String) -> UploadHost? {
        guard path.hasPrefix("/i/") else { return nil }
        switch setting {
        case "PicGo", "PicList": return .http
        case "uPic", "Picsee": return .app(setting)
        default: return nil
        }
    }

    // MARK: - Process Execution for uPic/Picsee
    nonisolated private func run(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        // Set a default PATH to ensure tools can be found
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe

        // Capture stderr to console for debugging
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            print("MiaoYan Shell Error: \(error)")
            return nil
        }

        final class ProcessOutput: @unchecked Sendable {
            var outputData = Data()
            var errorData = Data()
        }

        let semaphore = DispatchSemaphore(value: 0)
        let result = ProcessOutput()

        // Read stdout and stderr in parallel to avoid pipe deadlock
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            result.outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            result.errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        DispatchQueue.global(qos: .utility).async {
            group.wait()
            process.waitUntilExit()
            semaphore.signal()
        }

        // Wait with timeout
        let waitResult = semaphore.wait(timeout: .now() + 10.0)
        if waitResult == .timedOut {
            // Try graceful termination first
            process.terminate()

            // If still running after 1 second, force kill
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            DispatchQueue.global(qos: .utility).async {
                semaphore.wait()
                if !result.errorData.isEmpty, let errorStr = String(data: result.errorData, encoding: .utf8) {
                    print("MiaoYan Shell Stderr: \(errorStr)")
                }
            }
            print("MiaoYan Shell Timeout: Command exceeded 10 seconds")
            return nil
        }

        // Print stderr if any
        if !result.errorData.isEmpty, let errorStr = String(data: result.errorData, encoding: .utf8) {
            print("MiaoYan Shell Stderr: \(errorStr)")
        }

        return String(data: result.outputData, encoding: .utf8)
    }

    nonisolated private func uploadToCloudAsync(parameters: UploadParameters) {
        let localPath = parameters.localPath
        let originalPath = parameters.originalPath
        let picType = parameters.picType
        let textView = parameters.textView
        let note = parameters.note
        let placeholder = parameters.placeholder

        DispatchQueue.global(qos: .userInitiated).async {
            let executablePath = "/Applications/\(picType).app/Contents/MacOS/\(picType)"
            let runList = self.run(executablePath: executablePath, arguments: ["-o", "url", "-u", localPath])
            let imageDesc = runList?.components(separatedBy: "\n") ?? []

            var uploadedURL: String?
            for line in imageDesc {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedLine.hasPrefix("http://") || trimmedLine.hasPrefix("https://") {
                    uploadedURL = trimmedLine
                    break
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let validURL = uploadedURL {
                    self.replacePlaceholderWithURL(
                        placeholder: placeholder,
                        cloudURL: validURL,
                        textView: textView,
                        note: note
                    )
                    self.deleteImage(tempPath: URL(fileURLWithPath: localPath))
                    if let viewController = textView.window?.contentViewController {
                        viewController.toast(message: I18n.str("Image uploaded successfully"), style: .success)
                    }
                } else {
                    self.replacePlaceholderWithURL(
                        placeholder: placeholder,
                        cloudURL: originalPath,
                        textView: textView,
                        note: note
                    )
                    if let viewController = textView.window?.contentViewController {
                        viewController.toast(message: I18n.str("Upload failed. The local image was kept"), style: .failure)
                    }
                }
            }
        }
    }

    private func postToPicGo(imagePath: String, serverURL: String, completion: @escaping @Sendable (String?, Error?) -> Void) {
        guard let url = URL(string: serverURL) else {
            completion(nil, NSError(domain: "Invalid URL", code: -1, userInfo: nil))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: [String]] = [
            "list": [imagePath]
        ]

        do {
            request.httpBody = try JSONEncoder().encode(parameters)
        } catch {
            completion(nil, error)
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(nil, error)
                return
            }

            guard let data = data else {
                completion(nil, NSError(domain: "No Data", code: -1, userInfo: nil))
                return
            }

            // PicGo returns { "success": true, "result": ["url"] }
            // PicList might return similar structure
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                    let result = json["result"] as? [String],
                    let firstUrl = result.first, !firstUrl.isEmpty
                {
                    completion(firstUrl, nil)
                } else {
                    completion(nil, nil)
                }
            } catch {
                completion(nil, error)
            }
        }
        task.resume()
    }

    @MainActor private func deleteImage(tempPath: URL) {
        do {
            guard let resultingItemUrl = AppEnvironment.current.storage.systemTrashDestination(for: tempPath) else { return }
            try FileManager.default.moveItem(at: tempPath, to: resultingItemUrl)
        } catch {
            AppDelegate.trackError(error, context: "ClipboardManager.deleteImage")
        }
    }

    /// Returns whether the note now holds the cloud link instead of the placeholder.
    @discardableResult
    private func replacePlaceholderWithURL(placeholder: String, cloudURL: String, textView: EditTextView, note: Note) -> Bool {
        guard let storage = textView.textStorage else { return false }

        let replacement = "![](\(cloudURL))"
        let placeholderPattern = NSRegularExpression.escapedPattern(for: placeholder)

        guard let regex = try? NSRegularExpression(pattern: placeholderPattern) else { return false }

        // Primary path: placeholder is still raw text in textStorage.
        // Only valid while the storage still belongs to the note the upload
        // started in; after a note switch the buffer holds another note's
        // text and editing it here (plus the whole-buffer save below) would
        // cross-write content between files (#543).
        // NSRegularExpression works in UTF-16 space, so the search range must use
        // the NSString length, not String.count, or a non-ASCII prefix (emoji,
        // CJK surrogate pairs) would shrink the range and miss the placeholder.
        let storageContent = storage.string
        if textView.storageNote === note,
            let match = regex.firstMatch(in: storageContent, range: NSRange(location: 0, length: (storageContent as NSString).length))
        {
            // Going through shouldChangeText registers the swap with undo, so
            // Command-Z afterwards does not undo a stale range over the URL.
            if textView.shouldChangeText(in: match.range, replacementString: replacement) {
                storage.replaceCharacters(in: match.range, with: replacement)
                textView.didChangeText()
            } else {
                storage.replaceCharacters(in: match.range, with: replacement)
                textView.undoManager?.removeAllActions()
            }
            textView.saveTextStorageContent(to: note)
            note.save()
            return true
        }

        // Fallback: refillEditArea converted ![](uploading...) to an NSTextAttachment so
        // storage.string no longer contains the literal text. Search note.content (the raw
        // string synced from disk) instead, update it directly, then reload the editor.
        let rawContent = note.content.string
        if let match = regex.firstMatch(in: rawContent, range: NSRange(location: 0, length: (rawContent as NSString).length)) {
            note.content.replaceCharacters(in: match.range, with: replacement)
            note.save()
            if let vc = textView.window?.contentViewController as? ViewController {
                vc.refillEditArea(suppressSave: true)
            } else if textView.isShellHosted, textView.storageNote === note, #available(macOS 14, *),
                let shell = (NSApp.delegate as? AppDelegate)?.shellWindowController as? ShellWindowController
            {
                shell.model.editor.reload(note)
            }
            return true
        }
        return false
    }
}

/// Promised files of one drop, kept in drag order until the last arrives.
@MainActor
final class PromiseArrivals {
    private var files: [URL?]
    private var remaining: Int
    private let completion: ([URL]) -> Void

    /// `completion` gets every file that arrived, once the last promise has answered.
    init(count: Int, completion: @escaping ([URL]) -> Void) {
        files = Array(repeating: nil, count: count)
        remaining = count
        self.completion = completion
    }

    func arrive(_ url: URL?, at index: Int) {
        files[index] = url
        remaining -= 1
        if remaining == 0 { completion(files.compactMap { $0 }) }
    }

    /// The reader one promise calls with its file. AppKit calls it on the
    /// operation queue the receiver was given, so it must not belong to the
    /// main actor: a closure written inline in ClipboardManager did, and the
    /// first photo dropped on the editor crashed the app on its isolation check.
    nonisolated static func reader(for arrivals: PromiseArrivals, at index: Int) -> @Sendable (URL, Error?) -> Void {
        { url, error in
            Task { @MainActor in
                if let error { AppDelegate.trackError(error, context: "ClipboardManager.receivePromises") }
                arrivals.arrive(error == nil ? url : nil, at: index)
            }
        }
    }
}
