import Cocoa
import Foundation
import LocalAuthentication
import ZipArchive

@MainActor
public class Note: NSObject {
    @objc var title: String = ""
    var project: Project
    var container: NoteContainer = .none
    var type: NoteType = .markdown
    var url: URL

    var content: NSMutableAttributedString = .init()
    var creationDate: Date? = Date()
    var sharedStorage = Storage.sharedInstance()
    let dateFormatter = DateFormatter()
    let undoManager = UndoManager()
    public var originalExtension: String?

    public var name: String = ""
    public var preview: String = ""

    public var isPinned: Bool = false
    public var modifiedLocalAt = Date()

    public var imageUrl: [URL]?
    public var isParsed = false
    private var isContentLoaded = false

    // Debounce for save operations
    private var saveWorkItem: DispatchWorkItem?

    private var decryptedTemporarySrc: URL?
    public var ciphertextWriter = OperationQueue()

    private var lastSelectedRange: NSRange?

    init(url: URL, with project: Project) {
        ciphertextWriter.maxConcurrentOperationCount = 1
        ciphertextWriter.qualityOfService = .userInteractive

        self.url = url
        self.project = project

        super.init()

        parseURL(loadProject: false)
    }

    init(
        name: String? = nil,
        project: Project? = nil,
        type: NoteType? = nil
    ) {
        ciphertextWriter.maxConcurrentOperationCount = 1
        ciphertextWriter.qualityOfService = .userInteractive

        let resolvedProject = project ?? Storage.sharedInstance().getMainProject()
        let resolvedName =
            (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? name!
            : String()

        self.project = resolvedProject
        self.name = resolvedName

        self.type = type ?? .markdown
        let ext = self.type.fileExtension

        url = NameHelper.getUniqueFileName(
            name: resolvedName,
            project: resolvedProject,
            ext: ext)

        super.init()
        parseURL()
    }

    public func setLastSelectedRange(value: NSRange) {
        lastSelectedRange = value
    }

    public func getLastSelectedRange() -> NSRange? {
        lastSelectedRange
    }

    public func hasTitle() -> Bool {
        true
    }

    public func getURL() -> URL {
        if let url = decryptedTemporarySrc {
            return url
        }

        return url
    }

    public func loadProject(url: URL) {
        self.url = url

        if let project = sharedStorage.getProjectBy(url: url) {
            self.project = project
        }
    }

    func load() {
        if let attributedString = getContent() {
            content = NSMutableAttributedString(attributedString: attributedString)
            isContentLoaded = true
            return
        }
        isContentLoaded = false
    }

    func reload() -> Bool {
        guard let modifiedAt = getFileModifiedDate() else {
            return false
        }

        if modifiedAt != modifiedLocalAt {
            if let attributedString = getContent() {
                content = NSMutableAttributedString(attributedString: attributedString)
                isContentLoaded = true
            } else {
                isContentLoaded = false
            }
            loadModifiedLocalAt()
            return true
        }

        return false
    }

    public func forceReload() {
        if let attributedString = getContent() {
            content = NSMutableAttributedString(attributedString: attributedString)
            isContentLoaded = true
            return
        }
        isContentLoaded = false
    }

    func loadModifiedLocalAt() {
        guard let modifiedAt = getFileModifiedDate() else {
            modifiedLocalAt = Date()
            return
        }

        modifiedLocalAt = modifiedAt
    }

    public func getExtensionForContainer() -> String {
        type.fileExtension
    }

    public func getFileModifiedDate() -> Date? {
        do {
            let url = getURL()
            let path = url.path

            let attr = try FileManager.default.attributesOfItem(atPath: path)

            return attr[FileAttributeKey.modificationDate] as? Date
        } catch {
            AppDelegate.trackError(error, context: "Note.loadModificationDate")
            AppDelegate.trackError(error, context: "Note.getModificationDate")
            return nil
        }
    }

    func move(to: URL, project: Project? = nil) -> Bool {
        do {
            var destination = to

            if FileManager.default.fileExists(atPath: to.path) {
                guard let project = project ?? sharedStorage.getProjectBy(url: to) else { return false }

                let ext = getExtensionForContainer()
                destination = NameHelper.getUniqueFileName(name: title, project: project, ext: ext)
            }

            try FileManager.default.moveItem(at: url, to: destination)

            let restorePin = isPinned
            if isPinned {
                removePin()
            }

            overwrite(url: destination)

            if restorePin {
                addPin()
            }

        } catch {
            AppDelegate.trackError(error, context: "Note.moveFile")
            return false
        }

        return true
    }

    func getNewURL(name: String) -> URL {
        let escapedName =
            name
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: ":")

        var newUrl = url.deletingLastPathComponent()
        newUrl.appendPathComponent(escapedName + "." + url.pathExtension)
        return newUrl
    }

    public func remove() {
        if !isTrash(), !isEmpty() {
            if let trashURLs = removeFile() {
                url = trashURLs[0]
                parseURL()
            }
        } else {
            _ = removeFile()

            if isPinned {
                removePin()
            }
        }
    }

    public func getCursorPosition() -> Int? {
        var position: Int?

        if let data = try? url.extendedAttribute(forName: "com.tw93.miaoyan.cursor") {
            position = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int in
                ptr.load(as: Int.self)
            }

            return position
        }

        return nil
    }

    public func isEmpty() -> Bool {
        content.length == 0
    }

    func removeFile(completely: Bool = false) -> [URL]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        if isTrash() {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        do {
            guard let dst = Storage.sharedInstance().trashItem(url: url) else {
                var resultingItemUrl: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultingItemUrl)

                guard let dst = resultingItemUrl else { return nil }

                let originalURL = url
                overwrite(url: dst as URL)
                return [url, originalURL]
            }

            try FileManager.default.moveItem(at: url, to: dst)

            let originalURL = url
            overwrite(url: dst)
            return [url, originalURL]

        } catch {
            AppDelegate.trackError(error, context: "Note.trashError")
        }

        return nil
    }

    private func getDefaultTrashURL() -> URL? {
        if let url = sharedStorage.getDefaultTrash()?.url {
            return url
        }

        return nil
    }

    public func getPreviewLabel(with text: String? = nil) -> String {
        var preview = ""
        let content = text ?? content.string
        let length = text?.count ?? self.content.string.count

        if length > 250 {
            if text == nil {
                let startIndex = content.index(content.startIndex, offsetBy: 0)
                let endIndex = content.index(content.startIndex, offsetBy: 250)
                preview = String(content[startIndex...endIndex])
            } else {
                preview = String(content.prefix(250))
            }
        } else {
            preview = content
        }

        preview = preview.replacingOccurrences(of: "\n", with: " ")

        preview = preview.condenseWhitespace()

        if preview.starts(with: "![") {
            return ""
        }

        return preview
    }

    @objc public func getPreviewForLabel() -> String {
        getPreviewLabel()
    }

    @objc func getDateForLabel() -> String {
        guard
            let date = (project.sortBy == .creationDate || UserDefaultsManagement.sort == .creationDate)
                ? creationDate
                : modifiedLocalAt
        else { return String() }
        return dateFormatter.formatTimeForDisplay(date)
    }

    @objc func getCreationDateForLabel() -> String? {
        guard let creationDate = creationDate else { return nil }
        return dateFormatter.formatTimeForDisplay(creationDate)
    }

    @objc func getCreateTime() -> String? {
        guard let createDate = creationDate else { return nil }
        return dateFormatter.formatTimeForDisplay(createDate)
    }

    @objc func getUpdateTime() -> String? {
        guard let updateDate = getFileModifiedDate() else { return nil }
        return dateFormatter.formatTimeForDisplay(updateDate)
    }

    @objc func getRelativePath() -> String? {
        url.path.replacingOccurrences(of: UserDefaultsManagement.storagePath!, with: "")
    }

    func getContent() -> NSAttributedString? {
        guard let url = getContentFileURL() else { return nil }

        do {
            let options = getDocOptions()

            return try NSAttributedString(url: url, options: options, documentAttributes: nil)
        } catch {
            if let data = try? Data(contentsOf: url) {
                let encoding = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: nil, usedLossyConversion: nil)

                let options = getDocOptions(with: String.Encoding(rawValue: encoding))
                return try? NSAttributedString(url: url, options: options, documentAttributes: nil)
            }
        }

        return nil
    }

    func isMarkdown() -> Bool {
        type == .markdown
    }

    func addPin(cloudSave: Bool = true) {
        sharedStorage.pinned += 1
        isPinned = true
        var pin = true
        let data = Data(bytes: &pin, count: 1)
        try? url.setExtendedAttribute(data: data, forName: "\(Bundle.main.bundleIdentifier!).pin")
    }

    func removePin(cloudSave: Bool = true) {
        if isPinned {
            sharedStorage.pinned -= 1
            isPinned = false
            var pin = false
            let data = Data(bytes: &pin, count: 1)
            try? url.setExtendedAttribute(data: data, forName: "\(Bundle.main.bundleIdentifier!).pin")
        }
    }

    func togglePin() {
        if !isPinned {
            addPin()
        } else {
            removePin()
        }
    }

    private static let metaTitleRegex = try! NSRegularExpression(pattern: "title: (.*?)", options: [])

    func cleanMetaData(content: String) -> String {
        if content.hasPrefix("---\n") {
            var list = content.components(separatedBy: "---")

            if list.count > 2 {
                let headerList = list[1].components(separatedBy: "\n")
                for header in headerList {
                    let nsHeader = header as NSString
                    let matches = Note.metaTitleRegex.matches(in: String(nsHeader), options: [], range: NSRange(location: 0, length: (nsHeader as String).count))

                    if matches.first != nil {
                        list.remove(at: 1)
                        break
                    }
                }

                return list.joined()
            }
        }

        return content
    }

    func getPrettifiedContent() -> String {
        ensureContentLoaded()
        let content = NotesTextProcessor.convertAppLinks(in: content)
        return cleanMetaData(content: content.string)
    }

    public func overwrite(url: URL) {
        self.url = url

        parseURL()
    }

    func parseURL(loadProject: Bool = true) {
        if !url.pathComponents.isEmpty {
            container = .none
            name = url.pathComponents.last!

            if container == .none {
                type = .markdown
            }

            loadTitle()
        }

        if loadProject {
            self.loadProject(url: url)
        }
    }

    private func loadTitle() {
        title =
            url
            .deletingPathExtension()
            .pathComponents
            .last!
            .replacingOccurrences(of: ":", with: "/")
    }

    public func save(attributed: NSAttributedString) {
        let mutable = NSMutableAttributedString(attributedString: attributed)

        save(content: mutable)
    }

    public func save(content: NSMutableAttributedString) {
        self.content = content.unLoad()

        debounceSave(attributedString: self.content)
    }

    public func save(globalStorage: Bool = true) {
        if isMarkdown() {
            content = content.unLoadCheckboxes()
        }

        // Immediate save for manual requests or structure changes
        executeSave(attributedString: content, globalStorage: globalStorage)
    }

    private func debounceSave(attributedString: NSAttributedString, globalStorage: Bool = true) {
        saveWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.executeSave(attributedString: attributedString, globalStorage: globalStorage)
        }

        saveWorkItem = workItem
        // Debounce for 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func executeSave(attributedString: NSAttributedString, globalStorage: Bool = true) {
        // Cancel pending debounce if we are saving immediately
        saveWorkItem?.cancel()

        let attributes = getFileAttributes()

        do {
            let fileWrapper = getFileWrapper(attributedString: attributedString)

            let contentSrc: URL? = getContentFileURL()
            let dst = contentSrc ?? getURL()

            var originalContentsURL: URL?
            if let contentSrc = contentSrc {
                originalContentsURL = contentSrc
            }

            try fileWrapper.write(to: dst, options: .atomic, originalContentsURL: originalContentsURL)
            try FileManager.default.setAttributes(attributes, ofItemAtPath: dst.path)

            modifiedLocalAt = Date()
        } catch {
            AppDelegate.trackError(error, context: "Note.writeError")
            AppDelegate.trackError(error, context: "Note.write")

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = I18n.str("Save Failed")
                alert.informativeText = I18n.str(error.localizedDescription)
                alert.alertStyle = .warning
                alert.addButton(withTitle: I18n.str("OK"))
                alert.runModal()
            }
            return
        }

        if globalStorage {
            sharedStorage.add(self)
        }
    }

    public func getContentFileURL() -> URL? {
        let url = getURL()

        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        return nil
    }

    public func getFileWrapper(with imagesWrapper: FileWrapper? = nil) -> FileWrapper {
        let fileWrapper = getFileWrapper(attributedString: content)

        fileWrapper.filename = name

        return fileWrapper
    }

    func getFileAttributes() -> [FileAttributeKey: Any] {
        var attributes: [FileAttributeKey: Any] = [:]

        modifiedLocalAt = Date()

        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {}

        attributes[.modificationDate] = modifiedLocalAt
        return attributes
    }

    func getFileWrapper(attributedString: NSAttributedString) -> FileWrapper {
        do {
            let range = NSRange(location: 0, length: attributedString.length)
            let documentAttributes = getDocAttributes()
            return try attributedString.fileWrapper(from: range, documentAttributes: documentAttributes)
        } catch {
            return FileWrapper()
        }
    }

    func getTitleWithoutLabel() -> String {
        let title = url.deletingPathExtension().pathComponents.last!.replacingOccurrences(of: ":", with: "/")

        if title.isValidUUID {
            return ""
        }

        return title
    }

    func getDocOptions(with encoding: String.Encoding = .utf8) -> [NSAttributedString.DocumentReadingOptionKey: Any] {

        return [
            .documentType: NSAttributedString.DocumentType.plain,
            .characterEncoding: NSNumber(value: encoding.rawValue),
        ]
    }

    func getDocAttributes() -> [NSAttributedString.DocumentAttributeKey: Any] {
        var options: [NSAttributedString.DocumentAttributeKey: Any]

        options = [
            .documentType: NSAttributedString.DocumentType.plain,
            .characterEncoding: NSNumber(value: String.Encoding.utf8.rawValue),
        ]

        return options
    }

    func isTrash() -> Bool {
        project.isTrash
    }

    public func contains<S: StringProtocol>(terms: [S]) -> Bool {
        ensureContentLoaded()
        return name.localizedStandardContains(terms) || content.string.localizedStandardContains(terms)
    }

    private var excludeRanges = [NSRange]()

    public func getImageUrl(imageName: String) -> URL? {
        if imageName.starts(with: "http://") || imageName.starts(with: "https://") {
            return URL(string: imageName)
        }

        if imageName.starts(with: "/i/") {
            return project.url.appendingPathComponent(imageName)
        }

        if type == .markdown {
            return project.url.appendingPathComponent(imageName)
        }

        return nil
    }

    public func getImageCacheUrl() -> URL? {
        project.url.appendingPathComponent("/.cache/")
    }

    public func getAllImages(content: NSMutableAttributedString? = nil) -> [(url: URL, path: String)] {
        let content = content ?? self.content
        var res = [(url: URL, path: String)]()

        NotesTextProcessor.imageInlineRegex.regularExpression.enumerateMatches(
            in: content.string, options: NSRegularExpression.MatchingOptions(rawValue: 0), range: NSRange(0..<content.length),
            using: { result, _, _ in

                guard let range = result?.range(at: 3), content.length >= range.location else { return }

                let imagePath = content.attributedSubstring(from: range).string.removingPercentEncoding

                if let imagePath = imagePath, let url = self.getImageUrl(imageName: imagePath), !url.isRemote() {
                    res.append((url: url, path: imagePath))
                }
            })

        return res
    }

    public func getReferencedAttachmentPaths() -> Set<String> {
        var referenced = Set<String>()

        for image in getAllImages() {
            referenced.insert(image.url.path)
        }

        let noteString = content.string
        guard !noteString.isEmpty else { return referenced }

        let nsString = noteString as NSString
        let noteRange = NSRange(location: 0, length: nsString.length)

        Note.attachmentPathRegex.enumerateMatches(in: noteString, options: [], range: noteRange) { result, _, _ in
            guard let range = result?.range else { return }

            let rawPath = nsString.substring(with: range)
            for absolutePath in resolveAttachmentAbsolutePaths(for: rawPath) {
                referenced.insert(absolutePath)
            }
        }

        return referenced
    }

    private func resolveAttachmentAbsolutePaths(for rawPath: String) -> [String] {
        var variants = Set<String>()
        variants.insert(rawPath)

        if let decoded = rawPath.removingPercentEncoding {
            variants.insert(decoded)
        }

        var results = [String]()

        for variant in variants {
            if let absolute = resolveAttachmentAbsolutePath(forNormalizedPath: variant) {
                results.append(absolute)
            }
        }

        return results
    }

    private func resolveAttachmentAbsolutePath(forNormalizedPath path: String) -> String? {
        guard !path.isEmpty else { return nil }

        let projectPath = project.url.path

        if path.hasPrefix("/") {
            let resolved = NSString(string: projectPath + path).standardizingPath
            guard resolved.hasPrefix(projectPath) else { return nil }
            return resolved
        }

        var normalizedPath = path
        if normalizedPath.hasPrefix("./") {
            normalizedPath = String(normalizedPath.dropFirst(2))
        }

        if normalizedPath.hasPrefix("i/") || normalizedPath.hasPrefix("files/") {
            let resolved = NSString(string: projectPath + "/" + normalizedPath).standardizingPath
            guard resolved.hasPrefix(projectPath) else { return nil }
            return resolved
        }

        let noteDirectory = url.deletingLastPathComponent().path
        let resolvedRelative = NSString(string: noteDirectory).appendingPathComponent(normalizedPath)
        let standardized = NSString(string: resolvedRelative).standardizingPath
        guard standardized.hasPrefix(projectPath) else { return nil }

        return standardized
    }

    private static let attachmentPathRegex = try! NSRegularExpression(
        pattern: #"(?:(?:\.\./|\./|/)*)(?:i|files)/[^)\s'"]+"#,
        options: []
    )

    public func duplicate() {
        guard let duplicateName = getDupeName() else { return }

        let directory = url.deletingLastPathComponent()
        let duplicateURL = directory.appendingPathComponent(duplicateName).appendingPathExtension(url.pathExtension)

        try? FileManager.default.copyItem(at: self.url, to: duplicateURL)
    }

    public func getDupeName() -> String? {
        let fileName = url.deletingPathExtension().lastPathComponent
        let directory = url.deletingLastPathComponent()

        let baseName: String
        if fileName.hasSuffix(" Copy") {
            baseName = String(fileName.dropLast(5))  // Remove " Copy"
        } else if let range = fileName.range(of: " Copy ") {
            baseName = String(fileName[..<range.lowerBound])
        } else {
            baseName = fileName
        }

        var copyName = baseName + " Copy"
        var copyNumber = 2

        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(copyName).appendingPathExtension(url.pathExtension).path) {
            copyName = baseName + " Copy \(copyNumber)"
            copyNumber += 1
        }

        return copyName
    }

    public func dealContent() {
        loadTitleFromFileName()
        isParsed = true
    }

    private func loadTitleFromFileName() {
        let fileName = url.deletingPathExtension().pathComponents.last!.replacingOccurrences(of: ":", with: "/")

        title = fileName
    }

    public func invalidateCache() {
        imageUrl = nil
        preview = String()
        title = String()
        isParsed = false
        isContentLoaded = false
    }

    public func ensureContentLoaded() {
        if !isContentLoaded {
            load()
        }
    }

    public func markContentAsLoaded() {
        isContentLoaded = true
    }

    public func getMdImagePath(name: String) -> String {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        let name = encoded ?? name

        return "/i/\(name)"
    }

    public func isEqualURL(url: URL) -> Bool {
        url.path == self.url.path
    }

    public func append(string: NSMutableAttributedString) {
        content.append(string)
    }

    public func append(image data: Data, url: URL? = nil) {
        guard let path = ImagesProcessor.writeFile(data: data, url: url, note: self) else { return }

        var prefix = "\n\n"
        if content.length == 0 {
            prefix = String()
        }

        let markdown = NSMutableAttributedString(string: "\(prefix)![](\(path))")
        append(string: markdown)
    }

    @objc public func getName() -> String {
        if title.isValidUUID {
            return "Untitled Note"
        }

        return title
    }

    public func getCacheForPreviewImage(at url: URL) -> URL? {
        var temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        temporary.appendPathComponent("Preview")

        if let filePath = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
            return temporary.appendingPathComponent(filePath)
        }

        return nil
    }

    private func moveFilesFlatToAssets(note: Note, from imageURL: URL, imagePath: String, to dest: URL) {
        let dest = dest.appendingPathComponent("assets")
        let fileName = imageURL.lastPathComponent

        if !FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false, attributes: nil)
        }

        do {
            try FileManager.default.moveItem(at: imageURL, to: dest.appendingPathComponent(fileName))

            let prefix = "]("
            let postfix = ")"

            let find = prefix + imagePath + postfix
            let replace = prefix + "assets/" + imageURL.lastPathComponent + postfix

            guard find != replace else { return }

            while note.content.mutableString.contains(find) {
                let range = note.content.mutableString.range(of: find)
                note.content.replaceCharacters(in: range, with: replace)
            }
        } catch {
            AppDelegate.trackError(error, context: "Note.encrypt")
        }
    }

    private func moveFilesAssetsToFlat(content: URL, src: URL, project: Project) {
        guard let content = try? String(contentsOf: content) else { return }

        let mutableContent = NSMutableAttributedString(attributedString: NSAttributedString(string: content))

        let imagesMeta = getAllImages(content: mutableContent)
        for imageMeta in imagesMeta {
            let fileName = imageMeta.url.lastPathComponent
            var dst: URL?
            var prefix = "/files/"

            if imageMeta.url.isImage {
                prefix = "/i/"
            }

            dst = project.url.appendingPathComponent(prefix + fileName)

            guard let moveTo = dst else { continue }

            let dstDir = project.url.appendingPathComponent(prefix)
            let moveFrom = src.appendingPathComponent("assets/" + fileName)

            do {
                if !FileManager.default.fileExists(atPath: dstDir.path) {
                    try? FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: false, attributes: nil)
                }

                try FileManager.default.moveItem(at: moveFrom, to: moveTo)

            } catch {
                if let fileName = ImagesProcessor.getFileName(from: moveTo, to: dstDir, ext: moveTo.pathExtension) {
                    let moveTo = dstDir.appendingPathComponent(fileName)
                    try? FileManager.default.moveItem(at: moveFrom, to: moveTo)
                }
            }

            let find = "](assets/" + fileName + ")"
            let replace = "](" + prefix + fileName + ")"

            guard find != replace else { return }

            while mutableContent.mutableString.contains(find) {
                let range = mutableContent.mutableString.range(of: find)
                mutableContent.replaceCharacters(in: range, with: replace)
            }

            try? mutableContent.string.write(to: url, atomically: true, encoding: String.Encoding.utf8)
        }
    }

    private func cleanOut() {
        imageUrl = nil
        content = NSMutableAttributedString(string: String())
        preview = String()
        title = String()
    }

    private func removeTempContainer() {
        if let url = decryptedTemporarySrc {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func showIconInList() -> Bool {
        isPinned
    }

    public func getFileName() -> String {
        let fileName = url.deletingPathExtension().pathComponents.last!.replacingOccurrences(of: ":", with: "/")
        return fileName
    }

    public func getShortTitle() -> String {
        let fileName = getFileName()

        if fileName.isValidUUID {
            return ""
        }

        return fileName
    }

    public func getDefaultTitle() -> String? {
        return I18n.str("Untitled Note")
    }

    public func getTitle() -> String? {
        if !title.isEmpty {
            if title.isValidUUID {
                return getDefaultTitle()
            }

            if title.starts(with: "![") {
                return nil
            }

            return title
        }

        if getFileName().isValidUUID {
            let previewCharsQty = preview.count
            if previewCharsQty > 0 {
                return getDefaultTitle()
            }
        }

        return nil
    }

    public func getExportTitle() -> String {

        let title = getTitle() ?? getFileName()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedTitle = trimmedTitle.replacingOccurrences(of: "/", with: "_")

        return sanitizedTitle
    }

}
