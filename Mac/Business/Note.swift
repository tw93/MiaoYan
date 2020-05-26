import Foundation
import LocalAuthentication
import SSZipArchive

public class Note: NSObject {
    @objc var title: String = ""
    var project: Project
    var container: NoteContainer = .none
    var type: NoteType = .Markdown
    var url: URL

    var content: NSMutableAttributedString = NSMutableAttributedString()
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

    private var decryptedTemporarySrc: URL?
    public var ciphertextWriter = OperationQueue()

    private var lastSelectedRange: NSRange?

    // Load exist

    init(url: URL, with project: Project) {
        ciphertextWriter.maxConcurrentOperationCount = 1
        ciphertextWriter.qualityOfService = .userInteractive

        self.url = url
        self.project = project
        super.init()

        parseURL(loadProject: false)
    }

    // Make new

    init(name: String? = nil, project: Project? = nil, type: NoteType? = nil, cont: NoteContainer? = nil) {
        ciphertextWriter.maxConcurrentOperationCount = 1
        ciphertextWriter.qualityOfService = .userInteractive

        let project = project ?? Storage.sharedInstance().getMainProject()
        let name = name ?? String()

        self.project = project
        self.name = name

        container = cont ?? UserDefaultsManagement.fileContainer
        self.type = type ?? .Markdown

        let ext = container == .none
            ? self.type.getExtension(for: container)
            : "textbundle"

        url = NameHelper.getUniqueFileName(name: name, project: project, ext: ext)

        super.init()
        parseURL()
    }

    public func setLastSelectedRange(value: NSRange) {
        lastSelectedRange = value
    }

    public func getLastSelectedRange() -> NSRange? {
        return lastSelectedRange
    }

    public func hasTitle() -> Bool {
        return true
    }

    /// Important for decrypted temporary containers
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
        }
    }

    func reload() -> Bool {
        guard let modifiedAt = getFileModifiedDate() else {
            return false
        }

        if modifiedAt != modifiedLocalAt {
            if container != .encryptedTextPack, let attributedString = getContent() {
                content = NSMutableAttributedString(attributedString: attributedString)
            }
            loadModifiedLocalAt()
            return true
        }

        return false
    }

    public func forceReload() {
        if container != .encryptedTextPack, let attributedString = getContent() {
            content = NSMutableAttributedString(attributedString: attributedString)
        }
    }

    func loadModifiedLocalAt() {
        guard let modifiedAt = getFileModifiedDate() else {
            modifiedLocalAt = Date()
            return
        }

        modifiedLocalAt = modifiedAt
    }

    public func isTextBundle() -> Bool {
        return (container == .textBundle || container == .textBundleV2)
    }

    public func isFullLoadedTextBundle() -> Bool {
        return getContentFileURL() != nil
    }

    public func getExtensionForContainer() -> String {
        return type.getExtension(for: container)
    }

    public func getFileModifiedDate() -> Date? {
        do {
            let url = getURL()
            var path = url.path

            if isTextBundle() {
                if let url = getContentFileURL() {
                    path = url.path
                } else {
                    return nil
                }
            }

            let attr = try FileManager.default.attributesOfItem(atPath: path)

            return attr[FileAttributeKey.modificationDate] as? Date
        } catch {
            NSLog("Note modification date load error: \(error.localizedDescription)")
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

            #if os(OSX)
            let restorePin = isPinned
            if isPinned {
                removePin()
            }

            overwrite(url: destination)

            if restorePin {
                addPin()
            }
            #endif

            NSLog("File moved from \"\(url.deletingPathExtension().lastPathComponent)\" to \"\(destination.deletingPathExtension().lastPathComponent)\"")
        } catch {
            Swift.print(error)
            return false
        }

        return true
    }

    func getNewURL(name: String) -> URL {
        let escapedName = name
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

    public func isEmpty() -> Bool {
        return content.length == 0
    }

    #if os(iOS)
    // Return URL moved in
    func removeFile(completely: Bool = false) -> [URL]? {
        if FileManager.default.fileExists(atPath: url.path) {
            if isTrash() || completely || isEmpty() {
                try? FileManager.default.removeItem(at: url)
                return nil
            }

            guard let trashUrl = getDefaultTrashURL() else {
                print("Trash not found")

                var resultingItemUrl: NSURL?
                if #available(iOS 11.0, *) {
                    try? FileManager.default.trashItem(at: url, resultingItemURL: &resultingItemUrl)

                    if let result = resultingItemUrl, let path = result.path {
                        return [URL(fileURLWithPath: path), url]
                    }
                }

                return nil
            }

            var trashUrlTo = trashUrl.appendingPathComponent(name)

            if FileManager.default.fileExists(atPath: trashUrlTo.path) {
                let reserveName = "\(Int(Date().timeIntervalSince1970)) \(name)"
                trashUrlTo = trashUrl.appendingPathComponent(reserveName)
            }

            print("Note moved in custom Trash folder")
            try? FileManager.default.moveItem(at: url, to: trashUrlTo)

            return [trashUrlTo, url]
        }

        return nil
    }
    #endif

    #if os(OSX)
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
            print("Trash error: \(error)")
        }

        return nil
    }
    #endif

    private func getDefaultTrashURL() -> URL? {
        if let url = sharedStorage.getDefaultTrash()?.url {
            return url
        }

        return nil
    }

    public func getPreviewLabel(with text: String? = nil) -> String {
        var preview: String = ""
        let content = text ?? self.content.string
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
        return getPreviewLabel()
    }

    @objc func getDateForLabel() -> String {
        guard let date = (project.sortBy == .creationDate || UserDefaultsManagement.sort == .creationDate)
            ? creationDate
            : modifiedLocalAt
        else { return String() }

        let calendar = NSCalendar.current
        if calendar.isDateInToday(date) {
            return dateFormatter.formatTimeForDisplay(date)
        } else {
            return dateFormatter.formatDateForDisplay(date)
        }
    }

    @objc func getCreationDateForLabel() -> String? {
        guard let creationDate = self.creationDate else { return nil }
        return dateFormatter.formatDateForDisplay(creationDate)
    }

    func getContent() -> NSAttributedString? {
        guard container != .encryptedTextPack, let url = getContentFileURL() else { return nil }

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

    func isRTF() -> Bool {
        return type == .RichText
    }

    func isMarkdown() -> Bool {
        return type == .Markdown
    }

    func addPin(cloudSave: Bool = true) {
        sharedStorage.pinned += 1
        isPinned = true

        #if CLOUDKIT || os(iOS)
        if cloudSave {
            sharedStorage.saveCloudPins()
        }
        #elseif os(OSX)
        var pin = true
        let data = Data(bytes: &pin, count: 1)
        try? url.setExtendedAttribute(data: data, forName: "com.tw93.miaoyan.pin")
        #endif
    }

    func removePin(cloudSave: Bool = true) {
        if isPinned {
            sharedStorage.pinned -= 1
            isPinned = false

            #if CLOUDKIT || os(iOS)
            if cloudSave {
                sharedStorage.saveCloudPins()
            }
            #elseif os(OSX)
            var pin = false
            let data = Data(bytes: &pin, count: 1)
            try? url.setExtendedAttribute(data: data, forName: "com.tw93.miaoyan.pin")
            #endif
        }
    }

    func togglePin() {
        if !isPinned {
            addPin()
        } else {
            removePin()
        }
    }

    func cleanMetaData(content: String) -> String {
        var extractedTitle: String = ""

        if content.hasPrefix("---\n") {
            var list = content.components(separatedBy: "---")

            if list.count > 2 {
                let headerList = list[1].components(separatedBy: "\n")
                for header in headerList {
                    let nsHeader = header as NSString
                    let regex = try! NSRegularExpression(pattern: "title: \"(.*?)\"", options: [])
                    let matches = regex.matches(in: String(nsHeader), options: [], range: NSMakeRange(0, (nsHeader as String).count))

                    if let match = matches.first {
                        let range = match.range(at: 1)
                        extractedTitle = nsHeader.substring(with: range)
                        break
                    }
                }

                if extractedTitle.count > 0 {
                    list.removeSubrange(Range(0...1))

                    return "## " + extractedTitle + "\n\n" + list.joined()
                }

                return list.joined()
            }
        }

        return content
    }

    func getPrettifiedContent() -> String {
        var content = self.content.string

        #if NOT_EXTENSION || os(OSX)
        content = NotesTextProcessor.convertAppLinks(in: content)
        #endif

        return cleanMetaData(content: content)
    }

    public func overwrite(url: URL) {
        self.url = url

        parseURL()
    }

    func parseURL(loadProject: Bool = true) {
        if url.pathComponents.count > 0 {
            container = .withExt(rawValue: url.pathExtension)
            name = url.pathComponents.last!

            if isTextBundle() {
                let info = url.appendingPathComponent("info.json")

                if let jsonData = try? Data(contentsOf: info),
                    let info = try? JSONDecoder().decode(TextBundleInfo.self, from: jsonData) {
                    if info.version == 0x02 {
                        type = NoteType.withUTI(rawValue: info.type)
                        container = .textBundleV2
                        originalExtension = info.flatExtension
                    } else {
                        type = .Markdown
                        container = .textBundle
                    }
                }
            }

            if container == .none {
                type = .withExt(rawValue: url.pathExtension)
            }

            loadTitle()
        }

        if loadProject {
            self.loadProject(url: url)
        }
    }

    private func loadTitle() {
        title = url
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
        if isRTF() {
            #if os(OSX)
            self.content = content.unLoadUnderlines()
            #endif
        } else {
            self.content = content.unLoad()
        }

        save(attributedString: self.content)
    }

    public func save(globalStorage: Bool = true) {
        if isMarkdown() {
            content = content.unLoadCheckboxes()

            content = content.unLoadImages(note: self)
        }

        save(attributedString: content, globalStorage: globalStorage)
    }

    private func save(attributedString: NSAttributedString, globalStorage: Bool = true) {
        let url = getURL()
        let attributes = getFileAttributes()

        do {
            let fileWrapper = getFileWrapper(attributedString: attributedString)

            if isTextBundle() {
                if !FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: nil)

                    writeTextBundleInfo(url: url)
                }
            }

            let contentSrc: URL? = getContentFileURL()
            let dst = contentSrc ?? getContentSaveURL()

            var originalContentsURL: URL?
            if let contentSrc = contentSrc {
                originalContentsURL = contentSrc
            }

            try fileWrapper.write(to: dst, options: .atomic, originalContentsURL: originalContentsURL)
            try FileManager.default.setAttributes(attributes, ofItemAtPath: dst.path)

            modifiedLocalAt = Date()
        } catch {
            NSLog("Write error \(error)")
            return
        }

        if globalStorage {
            sharedStorage.add(self)
        }
    }

    private func getContentSaveURL() -> URL {
        let url = getURL()

        if isTextBundle() {
            let ext = getExtensionForContainer()
            return url.appendingPathComponent("text.\(ext)")
        }

        return url
    }

    public func getContentFileURL() -> URL? {
        var url = getURL()

        if isTextBundle() {
            let ext = getExtensionForContainer()
            url = url.appendingPathComponent("text.\(ext)")

            if !FileManager.default.fileExists(atPath: url.path) {
                url = url.deletingLastPathComponent()

                if let dirList = try? FileManager.default.contentsOfDirectory(atPath: url.path),
                    let first = dirList.first(where: { $0.starts(with: "text.") }) {
                    url = url.appendingPathComponent(first)

                    return url
                }

                return nil
            }

            return url
        }

        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        return nil
    }

    public func getFileWrapper(with imagesWrapper: FileWrapper? = nil) -> FileWrapper {
        let fileWrapper = getFileWrapper(attributedString: content)

        if isTextBundle() {
            let fileWrapper = getFileWrapper(attributedString: content)
            let info = getTextBundleJsonInfo()
            let infoWrapper = getFileWrapper(attributedString: NSAttributedString(string: info))

            let ext = getExtensionForContainer()
            let textBundle = FileWrapper(directoryWithFileWrappers: [
                "text.\(ext)": fileWrapper,
                "info.json": infoWrapper
            ])

            let assetsWrapper = imagesWrapper ?? getAssetsFileWrapper()
            textBundle.addFileWrapper(assetsWrapper)

            return textBundle
        }

        fileWrapper.filename = name

        return fileWrapper
    }

    private func getTextBundleJsonInfo() -> String {
        if let originalExtension = originalExtension {
            return """
            {
                "transient" : true,
                "type" : "\(type.uti)",
                "creatorIdentifier" : "com.tw93.miaoyan",
                "version" : 2,
                "flatExtension" : "\(originalExtension)"
            }
            """
        }

        return """
        {
            "transient" : true,
            "type" : "\(type.uti)",
            "creatorIdentifier" : "com.tw93.miaoyu",
            "version" : 2
        }
        """
    }

    private func getAssetsFileWrapper() -> FileWrapper {
        let wrapper = FileWrapper(directoryWithFileWrappers: [:])
        wrapper.preferredFilename = "assets"

        do {
            let assets = url.appendingPathComponent("assets")

            var isDir = ObjCBool(false)
            if FileManager.default.fileExists(atPath: assets.path, isDirectory: &isDir), isDir.boolValue {
                let files = try FileManager.default.contentsOfDirectory(atPath: assets.path)
                for file in files {
                    let fileData = try Data(contentsOf: assets.appendingPathComponent(file))
                    wrapper.addRegularFile(withContents: fileData, preferredFilename: file)
                }
            }
        } catch {
            print(error)
        }

        return wrapper
    }

    private func writeTextBundleInfo(url: URL) {
        let url = url.appendingPathComponent("info.json")
        let info = getTextBundleJsonInfo()

        try? info.write(to: url, atomically: true, encoding: String.Encoding.utf8)
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
        if type == .RichText {
            return [.documentType: NSAttributedString.DocumentType.rtf]
        }

        return [
            .documentType: NSAttributedString.DocumentType.plain,
            .characterEncoding: NSNumber(value: encoding.rawValue)
        ]
    }

    func getDocAttributes() -> [NSAttributedString.DocumentAttributeKey: Any] {
        var options: [NSAttributedString.DocumentAttributeKey: Any]

        if type == .RichText {
            options = [
                .documentType: NSAttributedString.DocumentType.rtf
            ]
        } else {
            options = [
                .documentType: NSAttributedString.DocumentType.plain,
                .characterEncoding: NSNumber(value: String.Encoding.utf8.rawValue)
            ]
        }

        return options
    }

    func isTrash() -> Bool {
        return project.isTrash
    }

    public func contains<S: StringProtocol>(terms: [S]) -> Bool {
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

        if isTextBundle() {
            return getURL().appendingPathComponent(imageName)
        }

        if type == .Markdown {
            return project.url.appendingPathComponent(imageName)
        }

        return nil
    }

    public func getImageCacheUrl() -> URL? {
        return project.url.appendingPathComponent("/.cache/")
    }

    public func getAllImages(content: NSMutableAttributedString? = nil) -> [(url: URL, path: String)] {
        let content = content ?? self.content
        var res = [(url: URL, path: String)]()

        NotesTextProcessor.imageInlineRegex.regularExpression.enumerateMatches(in: content.string, options: NSRegularExpression.MatchingOptions(rawValue: 0), range: NSRange(0..<content.length), using:
            { (result, _, _) -> Void in

                guard let range = result?.range(at: 3), content.length >= range.location else { return }

                let imagePath = content.attributedSubstring(from: range).string.removingPercentEncoding

                if let imagePath = imagePath, let url = self.getImageUrl(imageName: imagePath), !url.isRemote() {
                    res.append((url: url, path: imagePath))
                }
        })

        return res
    }

    #if os(OSX)

    public func duplicate() {
        var url = self.url
        let ext = url.pathExtension
        url.deletePathExtension()

        let name = url.lastPathComponent
        url.deleteLastPathComponent()

        let now = dateFormatter.formatForDuplicate(Date())
        url.appendPathComponent(name + " " + now)
        url.appendPathExtension(ext)

        try? FileManager.default.copyItem(at: self.url, to: url)
    }

    public func getDupeName() -> String? {
        var url = self.url
        url.deletePathExtension()

        let name = url.lastPathComponent
        url.deleteLastPathComponent()

        let now = dateFormatter.formatForDuplicate(Date())
        return name + " " + now
    }
    #endif

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
    }

    public func getMdImagePath(name: String) -> String {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        let name = encoded ?? name

        if isTextBundle() {
            return "assets/\(name)"
        }

        return "/i/\(name)"
    }

    public func isEqualURL(url: URL) -> Bool {
        return url.path == self.url.path
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

    private func convertFlatToTextBundle() -> URL {
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        let temporaryProject = Project(url: temporary)

        let currentName = url.deletingPathExtension().lastPathComponent
        let note = Note(name: currentName, project: temporaryProject, type: type, cont: .textBundleV2)

        note.originalExtension = url.pathExtension
        note.content = content
        note.save(globalStorage: false)

        if type == .Markdown {
            let imagesMeta = getAllImages()
            for imageMeta in imagesMeta {
                moveFilesFlatToAssets(note: note, from: imageMeta.url, imagePath: imageMeta.path, to: note.url)
            }

            note.save(globalStorage: false)
        }

        return note.url
    }

    private func convertTextBundleToFlat(name: String) {
        let textBundleURL = url
        let json = textBundleURL.appendingPathComponent("info.json")

        if let jsonData = try? Data(contentsOf: json),
            let info = try? JSONDecoder().decode(TextBundleInfo.self, from: jsonData) {
            if let flatExtension = info.flatExtension {
                let ext = NoteType.withUTI(rawValue: info.type).getExtension(for: .textBundleV2)
                let fileName = "text.\(ext)"

                let uniqueURL = NameHelper.getUniqueFileName(name: name, project: project, ext: flatExtension)
                let flatURL = url.appendingPathComponent(fileName)

                url = uniqueURL
                type = .withExt(rawValue: flatExtension)
                container = .none

                try? FileManager.default.moveItem(at: flatURL, to: uniqueURL)

                moveFilesAssetsToFlat(content: uniqueURL, src: textBundleURL, project: project)

                try? FileManager.default.removeItem(at: textBundleURL)
            }
        }
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
            print("Enc error: \(error)")
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

    private func loadTextBundle() -> Bool {
        do {
            let url = getURL()
            let json = url.appendingPathComponent("info.json")
            let jsonData = try Data(contentsOf: json)
            let info = try JSONDecoder().decode(TextBundleInfo.self, from: jsonData)

            type = .withUTI(rawValue: info.type)

            if info.version == 1 {
                container = .textBundle
                return true
            }

            container = .textBundleV2
            return true
        } catch {
            print("Can not load TextBundle: \(error)")
        }

        return false
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
        return isPinned
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

    public func getTitle() -> String? {
        
        if title.isValidUUID {
            return "未命名"
        }
        
        if title.count > 0 {
            return title
        }

        if getFileName().isValidUUID {
            return "未命名"
        }

        return nil
    }
}
