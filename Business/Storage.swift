import Cocoa
import CoreServices
import Foundation
import UniformTypeIdentifiers

struct DirectoryItem {
    let url: URL
    let modificationDate: Date
    let creationDate: Date
}

@MainActor
class Storage {
    static var instance: Storage?

    var noteList = [Note]()
    private var projects = [Project]()
    private var imageFolders = [URL]()

    public var tagNames = [String]()
    public var tags = [String]()

    var notesDict: [String: Note] = [:]

    private struct LoadedProjectInfo {
        let lastScan: Date
        let contentModifiedAt: Date?
        let hadError: Bool
    }

    private var loadedProjectInfo: [String: LoadedProjectInfo] = [:]

    var allowedExtensions = [
        "md", "markdown",
        "txt",
    ]
    private static let attachmentDirectoryNames = ["i", "files"]

    var pinned: Int = 0

    private var bookmarks = [URL]()
    private var scopedStorageURL: URL?

    init() {
        guard var url = UserDefaultsManagement.storageUrl else {
            return
        }

        // Start accessing security scoped resource if bookmark-based
        if UserDefaultsManagement.storageBookmark != nil {
            if url.startAccessingSecurityScopedResource() {
                scopedStorageURL = url
            }
        }

        if UserDefaultsManagement.isSingleMode, !UserDefaultsManagement.singleModePath.isEmpty {
            let singleModeUrl = URL(fileURLWithPath: UserDefaultsManagement.singleModePath)
            if !FileManager.default.directoryExists(atUrl: singleModeUrl) {
                url = singleModeUrl.deletingLastPathComponent()
            } else {
                url = singleModeUrl
            }
        }

        var name = url.lastPathComponent

        if let iCloudURL = getCloudDrive(), iCloudURL == url {
            name = "iCloud Drive"
        }

        let project = Project(url: url, label: name, isRoot: true, isDefault: true)

        _ = add(project: project)

        checkTrashForVolume(url: project.url)

        for url in bookmarks {
            if url.pathExtension == "css" {
                continue
            }

            guard !projectExist(url: url) else {
                continue
            }

            let project = Project(url: url, label: url.lastPathComponent, isRoot: true)
            _ = add(project: project)
        }
    }

    public func getChildProjects(project: Project) -> [Project] {
        projects.filter {
            $0.parent == project
        }
        .sorted(by: { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending })
    }

    public func getRootProject() -> Project? {
        projects.first(where: { $0.isRoot })
    }

    public func getDefault() -> Project? {
        projects.first(where: { $0.isDefault })
    }

    public func getRootProjects() -> [Project] {
        projects.filter(\.isRoot).sorted(by: { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending })
    }

    public func getDefaultTrash() -> Project? {
        projects.first(where: { $0.isTrash })
    }

    private func checkSub(url: URL, parent: Project) -> [Project] {
        var added = [Project]()
        let parentPath = url.path + "/i/"
        let filesPath = url.path + "/files/"

        if let subFolders = getSubFolders(url: url) {
            for subFolder in subFolders {
                if subFolder.lastPathComponent == "i" {
                    imageFolders.append(subFolder as URL)
                    continue
                }

                if projects.count > 100 {
                    return added
                }

                let subUrl = subFolder as URL

                guard !projectExist(url: subUrl),
                    subUrl.lastPathComponent != "i",
                    subUrl.lastPathComponent != "files",
                    !subUrl.path.contains(".Trash"),
                    !subUrl.path.contains("Trash"),
                    !subUrl.path.contains("/."),
                    !subUrl.path.contains(parentPath),
                    !subUrl.path.contains(filesPath),
                    true
                else {
                    continue
                }
                let project = Project(url: subUrl, label: subUrl.lastPathComponent, parent: parent)
                projects.append(project)
                added.append(project)
            }
        }

        return added
    }

    private func checkTrashForVolume(url: URL) {
        if UserDefaultsManagement.isSingleMode {
            return
        }

        var trashURL = getTrash(url: url)
        var needsTrashCreation = true

        if let currentTrash = trashURL, FileManager.default.fileExists(atPath: currentTrash.path) {
            needsTrashCreation = false
        }

        if needsTrashCreation {
            guard let trash = getDefault()?.url.appendingPathComponent("Trash") else {
                return
            }

            var isDir = ObjCBool(false)
            if !FileManager.default.fileExists(atPath: trash.path, isDirectory: &isDir) || !isDir.boolValue {
                do {
                    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false, attributes: nil)
                } catch {
                    AppDelegate.trackError(error, context: "Storage.trashDir")
                }
            }

            trashURL = trash
        }

        if let trashURL = trashURL {
            guard !projectExist(url: trashURL) else {
                return
            }

            let project = Project(url: trashURL, isTrash: true)
            projects.append(project)
        }
    }

    private func getCloudDrive() -> URL? {
        if let iCloudDocumentsURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents").resolvingSymlinksInPath() {
            var isDirectory = ObjCBool(true)
            if FileManager.default.fileExists(atPath: iCloudDocumentsURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return iCloudDocumentsURL
            }
        }

        return nil
    }

    func projectExist(url: URL) -> Bool {
        projects.contains(where: { $0.url == url })
    }

    public func removeBy(project: Project) {
        let list = noteList.filter {
            $0.project == project
        }

        for note in list {
            if let i = noteList.firstIndex(where: { $0 === note }) {
                noteList.remove(at: i)
            }
        }

        if let i = projects.firstIndex(of: project) {
            projects.remove(at: i)
        }
        loadedProjectInfo.removeValue(forKey: project.url.path)
    }

    public func add(project: Project) -> [Project] {
        var added = [Project]()

        if !projects.contains(project) {
            projects.append(project)
            added.append(project)
        }

        if project.isRoot, !UserDefaultsManagement.isSingleMode {
            let addedSubProjects = checkSub(url: project.url, parent: project)
            added += addedSubProjects
        }

        return added
    }

    func getTrash(url: URL) -> URL? {
        return try? FileManager.default.url(for: .trashDirectory, in: .allDomainsMask, appropriateFor: url, create: false)
    }

    public func getBookmarks() -> [URL] {
        bookmarks
    }

    public static func sharedInstance() -> Storage {
        guard let storage = instance else {
            instance = Storage()
            return instance!
        }
        return storage
    }

    public func loadProjects(withTrash: Bool = false, skipRoot: Bool = false) {
        if !skipRoot {
            noteList.removeAll()
            loadedProjectInfo.removeAll()
        }

        for project in projects {
            if project.isTrash, !withTrash {
                continue
            }

            if project.isRoot, skipRoot {
                continue
            }
            if UserDefaultsManagement.isSingleMode {
                let singleModeUrl = URL(fileURLWithPath: UserDefaultsManagement.singleModePath)
                let singleRootUrl = singleModeUrl.deletingLastPathComponent()

                if project.url == singleModeUrl {
                    loadLabel(project)
                }
                if project.url == singleRootUrl {
                    loadLabel(project)
                }
            } else {
                loadLabel(project)
            }
        }
    }

    func loadDocuments(tryCount: Int = 0, completion: @escaping () -> Void) {
        _ = restoreCloudPins()

        noteList = sortNotes(noteList: noteList, filter: "")

        guard !checkFirstRun() else {
            if tryCount == 0 {
                loadProjects()
                loadDocuments(tryCount: 1) {}
                return
            }
            return
        }
    }

    public func getMainProject() -> Project {
        projects.first!
    }

    public func getProjects() -> [Project] {
        projects
    }

    public func getProjectBy(element: Int) -> Project? {
        if projects.indices.contains(element) {
            return projects[element]
        }

        return nil
    }

    public func getCloudDriveProjects() -> [Project] {
        projects.filter {
            $0.isCloudDrive == true
        }
    }

    public func getLocalProjects() -> [Project] {
        projects.filter {
            $0.isCloudDrive == false
        }
    }

    public func getProjectPaths() -> [String] {
        var pathList: [String] = []
        let projects = getProjects()

        for project in projects {
            pathList.append(NSString(string: project.url.path).expandingTildeInPath)
        }

        return pathList
    }

    public func getProjectBy(url: URL) -> Project? {
        let projectURL = url.deletingLastPathComponent()
        let path = projectURL.path

        // Find all projects that could be parents (prefix match)
        let candidates = projects.filter { project in
            let projectPath = project.url.path
            if path == projectPath {
                return true
            }
            let normalized = projectPath.hasSuffix("/") ? projectPath : projectPath + "/"
            return path.hasPrefix(normalized)
        }

        // Return the one with the longest path (most specific match)
        return candidates.max(by: { $0.url.path.count < $1.url.path.count })
    }

    func sortNotes(noteList: [Note], filter: String, project: Project? = nil, operation: Operation? = nil) -> [Note] {
        let hasFilter = !filter.isEmpty

        return noteList.sorted(by: {
            if let operation = operation, operation.isCancelled {
                return false
            }

            if hasFilter {
                let firstMatch = $0.title.range(of: filter, options: [.caseInsensitive, .anchored]) != nil
                if firstMatch {
                    let secondMatch = $1.title.range(of: filter, options: [.caseInsensitive, .anchored]) != nil
                    if secondMatch {
                        return sortQuery(note: $0, next: $1, project: project)
                    }
                    return true
                }
            }

            return sortQuery(note: $0, next: $1, project: project)
        })
    }

    private func sortQuery(note: Note, next: Note, project: Project?) -> Bool {
        let sortDirection: SortDirection = UserDefaultsManagement.sortDirection ? .desc : .asc

        let sort = UserDefaultsManagement.sort

        if note.isPinned == next.isPinned {
            switch sort {
            case .creationDate:
                if let prevDate = note.creationDate, let nextDate = next.creationDate {
                    return sortDirection == .asc && prevDate < nextDate || sortDirection == .desc && prevDate > nextDate
                }
            case .modificationDate, .none:
                return sortDirection == .asc && note.modifiedLocalAt < next.modifiedLocalAt || sortDirection == .desc && note.modifiedLocalAt > next.modifiedLocalAt
            case .title:
                let result = note.title.localizedCaseInsensitiveCompare(next.title)
                return sortDirection == .asc && result == .orderedAscending || sortDirection == .desc && result == .orderedDescending
            }
        }

        return note.isPinned && !next.isPinned
    }

    func loadLabel(_ item: Project, loadContent: Bool = false) {
        let result = readDirectoryWithStatus(item.url)
        let documents = result.items
        let contentModifiedAt = directoryContentModifiedAt(item.url)

        for document in documents {
            let url = document.url

            if let currentNoteURL = EditTextView.note?.url,
                currentNoteURL == url
            {
                continue
            }

            let note = Note(url: url.resolvingSymlinksInPath(), with: item)

            if url.pathComponents.isEmpty {
                continue
            }

            note.modifiedLocalAt = document.modificationDate
            note.creationDate = document.creationDate
            note.project = item

            #if CLOUDKIT
            #else
                if let data = try? note.url.extendedAttribute(forName: "\(Bundle.main.bundleIdentifier!).pin") {
                    let isPinned = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Bool in
                        ptr.load(as: Bool.self)
                    }

                    note.isPinned = isPinned
                }
            #endif

            if loadContent {
                note.load()
            }

            if note.isPinned {
                pinned += 1
            }

            noteList.append(note)
        }
        loadedProjectInfo[item.url.path] = LoadedProjectInfo(
            lastScan: Date(),
            contentModifiedAt: contentModifiedAt,
            hadError: result.hadError
        )
    }

    public func loadMissingNotes(for project: Project) {
        let projectPath = project.url.path
        let now = Date()
        let contentModifiedAt = directoryContentModifiedAt(project.url)

        if let info = loadedProjectInfo[projectPath] {
            if !info.hadError {
                if project.isCloudDrive {
                    if now.timeIntervalSince(info.lastScan) < 2.0 {
                        return
                    }
                } else {
                    if let contentModifiedAt = contentModifiedAt,
                        contentModifiedAt == info.contentModifiedAt
                    {
                        return
                    }

                    if contentModifiedAt == nil,
                        now.timeIntervalSince(info.lastScan) < 1.0
                    {
                        return
                    }
                }
            } else if now.timeIntervalSince(info.lastScan) < 2.0 {
                return
            }
        }

        let result = readDirectoryWithStatus(project.url)
        let documents = result.items

        for document in documents {
            let url = document.url

            // Check if note is already loaded to avoid duplicates
            if noteList.contains(where: { $0.url == url }) {
                continue
            }

            let note = Note(url: url.resolvingSymlinksInPath(), with: project)

            if url.pathComponents.isEmpty {
                continue
            }

            note.modifiedLocalAt = document.modificationDate
            note.creationDate = document.creationDate
            note.project = project

            #if CLOUDKIT
            #else
                if let data = try? note.url.extendedAttribute(forName: "\(Bundle.main.bundleIdentifier!).pin") {
                    let isPinned = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Bool in
                        ptr.load(as: Bool.self)
                    }
                    note.isPinned = isPinned
                }
            #endif

            if note.isPinned {
                pinned += 1
            }

            noteList.append(note)
        }
        loadedProjectInfo[projectPath] = LoadedProjectInfo(
            lastScan: now,
            contentModifiedAt: contentModifiedAt,
            hadError: result.hadError
        )
    }

    public func unload(project: Project) {
        let notes = noteList.filter { $0.project == project }
        for note in notes {
            if let i = noteList.firstIndex(where: { $0 === note }) {
                noteList.remove(at: i)
            }
        }
        loadedProjectInfo.removeValue(forKey: project.url.path)
    }

    public func reLoadTrash() {
        noteList.removeAll(where: { $0.isTrash() })

        for project in projects where project.isTrash {
            loadLabel(project, loadContent: true)
        }
    }

    private func directoryContentModifiedAt(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private struct DirectoryReadResult {
        let items: [DirectoryItem]
        let hadError: Bool
    }

    private func readDirectoryWithStatus(_ url: URL) -> DirectoryReadResult {
        let url = url.resolvingSymlinksInPath()

        do {
            let directoryFiles =
                try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .typeIdentifierKey], options: .skipsHiddenFiles)

            let items =
                directoryFiles.filter {
                    allowedExtensions.contains($0.pathExtension)
                        && isValidUTI(url: $0)
                }
                .map { url in
                    DirectoryItem(
                        url: url,
                        modificationDate: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast,
                        creationDate: (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    )
                }
            return DirectoryReadResult(items: items, hadError: false)
        } catch {
            AppDelegate.trackError(error, context: "Storage.notFound: \(url.path)")
        }

        return DirectoryReadResult(items: [], hadError: true)
    }

    public func readDirectory(_ url: URL) -> [DirectoryItem] {
        readDirectoryWithStatus(url).items
    }

    public func isValidUTI(url: URL) -> Bool {
        guard url.fileSize < 100_000_000 else {
            return false
        }

        guard let typeIdentifier = (try? url.resourceValues(forKeys: [.typeIdentifierKey]))?.typeIdentifier else {
            return false
        }

        guard let utType = UTType(typeIdentifier) else {
            return false
        }

        if utType.conforms(to: .directory) {
            return false
        }

        return utType.conforms(to: .text)
            || utType.conforms(to: .plainText)
            || typeIdentifier == "net.daringfireball.markdown"
            || typeIdentifier == "public.markdown"
    }

    func add(_ note: Note) {
        if !noteList.contains(where: { $0.name == note.name && $0.project == note.project }) {
            noteList.append(note)
        }
    }

    func removeBy(note: Note) {
        if let i = noteList.firstIndex(where: { $0 === note }) {
            noteList.remove(at: i)
        }
    }

    func getNextId() -> Int {
        noteList.count
    }

    func checkFirstRun() -> Bool {
        guard noteList.isEmpty, let resourceURL = Bundle.main.resourceURL else {
            return false
        }

        guard let destination = getDemoSubdirURL() else {
            return false
        }

        let initialPath = resourceURL.appendingPathComponent("Initial").path

        // Skip directory structure in single mode
        if UserDefaultsManagement.isSingleMode {
            return true
        }

        // Detect system language
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false

        // Define folder structure
        let folders = ["Guide", "Examples", "Notes", "Ideas"]

        // File distribution mapping
        let fileMapping: [String: [String]] = [
            "Guide": [
                isChinese ? "介绍妙言.md" : "Introduction to MiaoYan.md"
            ],
            "Examples": [
                isChinese ? "妙言 PPT.md" : "MiaoYan PPT.md",
                isChinese ? "妙言 Markdown 语法指南.md" : "MiaoYan Markdown Syntax Guide.md",
            ],
            "Notes": [
                isChinese ? "欢迎使用.md" : "Welcome.md"
            ],
            "Ideas": [
                isChinese ? "头脑风暴.md" : "Brainstorming.md"
            ],
        ]

        do {
            // Create folders and copy files
            for folder in folders {
                let folderURL = destination.appendingPathComponent(folder)
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)

                if let files = fileMapping[folder] {
                    for file in files {
                        let sourcePath = "\(initialPath)/\(file)"
                        let destPath = folderURL.appendingPathComponent(file).path

                        if FileManager.default.fileExists(atPath: sourcePath) {
                            try? FileManager.default.copyItem(atPath: sourcePath, toPath: destPath)
                        }
                    }
                }
            }

            // Rescan subdirectories and add them as projects
            guard let rootProject = getRootProject() else {
                return false
            }
            _ = checkSub(url: rootProject.url, parent: rootProject)
        } catch {
            AppDelegate.trackError(error, context: "Storage.initialSetup")
            return false
        }

        return true
    }

    func getBy(url: URL) -> Note? {
        if noteList.isEmpty {
            return nil
        }

        let resolvedPath = url.path.lowercased()

        return
            noteList.first(where: {
                $0.url.path.lowercased() == resolvedPath
                    || "/private" + $0.url.path.lowercased() == resolvedPath

            })
    }

    func getBy(name: String) -> Note? {
        noteList.first(where: {
            $0.name == name

        })
    }

    func getBy(title: String) -> Note? {
        noteList.first(where: {
            $0.title.lowercased() == title.lowercased()

        })
    }

    func getBy(startWith: String) -> [Note]? {
        noteList.filter {
            $0.title.starts(with: startWith)
        }
    }

    func getDemoSubdirURL() -> URL? {
        if let project = projects.first {
            return project.url
        }

        return nil
    }

    func removeNotes(notes: [Note], fsRemove: Bool = true, completely: Bool = false, completion: @escaping ([URL: URL]?) -> Void) {
        guard !notes.isEmpty else {
            completion(nil)
            return
        }

        for note in notes {
            removeBy(note: note)
        }

        var removed = [URL: URL]()

        if fsRemove {
            for note in notes {
                if let trashURLs = note.removeFile(completely: completely) {
                    removed[trashURLs[0]] = trashURLs[1]
                }
            }
        }

        if !removed.isEmpty {
            completion(removed)
        } else {
            completion(nil)
        }
    }

    func getSubFolders(url: URL) -> [NSURL]? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]

        guard let fileEnumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: options) else {
            return nil
        }

        var extensions = allowedExtensions
        // Common image and file extensions to skip as "folders"
        for ext in ["jpg", "png", "gif", "jpeg", "json", "JPG", "PNG", ".icloud"] {
            extensions.append(ext)
        }
        // Specific folder names to skip
        let skipFolders = Set(["assets", ".cache", "i", ".Trash", "files"])

        var subDirs = [NSURL]()

        for case let fileURL as URL in fileEnumerator {
            // Skip check for extensions (optimization: check extension first as it's faster)
            if extensions.contains(fileURL.pathExtension) { continue }

            // Skip check for specific folder names
            if skipFolders.contains(fileURL.lastPathComponent) { continue }

            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))

                // Explicitly check for directory and not a package
                if let isDirectory = resourceValues.isDirectory, isDirectory,
                    let isPackage = resourceValues.isPackage, !isPackage
                {
                    subDirs.append(fileURL as NSURL)
                }
            } catch {
                continue
            }
        }

        return subDirs
    }

    public func getCurrentProject() -> Project? {
        projects.first
    }

    public func getAllTrash() -> [Note] {
        noteList.filter {
            $0.isTrash()
        }
    }

    public func initiateCloudDriveSync() {
        for project in projects {
            syncDirectory(url: project.url)
        }

        for imageFolder in imageFolders {
            syncDirectory(url: imageFolder)
        }
    }

    public func syncDirectory(url: URL) {
        do {
            let directoryFiles =
                try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey])

            let files =
                directoryFiles.filter {
                    !isDownloaded(url: $0)
                }

            let images = files.map { url in
                (
                    url,
                    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast,
                    (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                )
            }

            for image in images {
                let url = image.0 as URL

                if FileManager.default.isUbiquitousItem(at: url) {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                }
            }
        } catch {
        }
    }

    public func findOrphanAttachments(completion: @escaping @MainActor ([URL]) -> Void) {
        let referenced = collectReferencedAttachmentPaths()
        let attachmentFolders = collectAttachmentFolders()

        DispatchQueue.global(qos: .userInitiated).async {
            let orphaned = Storage.scanOrphanAttachments(folders: attachmentFolders, referenced: referenced)

            DispatchQueue.main.async {
                completion(orphaned)
            }
        }
    }

    private func collectAttachmentFolders() -> [URL] {
        var folders = [URL]()
        let manager = FileManager.default

        for project in projects where !project.isTrash {
            for folderName in Storage.attachmentDirectoryNames {
                let folderURL = project.url.appendingPathComponent(folderName)
                var isDir = ObjCBool(false)

                if manager.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue {
                    folders.append(folderURL)
                }
            }
        }

        return folders
    }

    nonisolated private static func scanOrphanAttachments(folders: [URL], referenced: Set<String>) -> [URL] {
        var orphaned = [URL]()
        let manager = FileManager.default

        for folderURL in folders {
            guard let enumerator = manager.enumerator(at: folderURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                if shouldSkipAttachmentCandidate(fileURL) {
                    continue
                }

                if !referenced.contains(fileURL.path) {
                    orphaned.append(fileURL)
                }
            }
        }

        return orphaned
    }

    public func removeAttachments(urls: [URL]) -> (removed: [URL], failed: [URL]) {
        var removed = [URL]()
        var failed = [URL]()
        let manager = FileManager.default

        for url in urls {
            do {
                var resultingItemUrl: NSURL?
                try manager.trashItem(at: url, resultingItemURL: &resultingItemUrl)
                removed.append(url)
            } catch {
                do {
                    try manager.removeItem(at: url)
                    removed.append(url)
                } catch {
                    failed.append(url)
                    AppDelegate.trackError(error, context: "Storage.cleanOrphanAttachments")
                }
            }
        }

        return (removed, failed)
    }

    private func collectReferencedAttachmentPaths() -> Set<String> {
        var referenced = Set<String>()

        for note in noteList {
            referenced.formUnion(note.getReferencedAttachmentPaths())
        }

        return referenced
    }

    nonisolated private static func shouldSkipAttachmentCandidate(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return true
        }

        let name = url.lastPathComponent
        if name.hasPrefix(".") || name.hasSuffix(".icloud") {
            return true
        }

        return false
    }

    public func isDownloaded(url: URL) -> Bool {
        var isDownloaded: AnyObject?

        do {
            try (url as NSURL).getResourceValue(&isDownloaded, forKey: URLResourceKey.ubiquitousItemDownloadingStatusKey)
        } catch _ {}

        if isDownloaded as? URLUbiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current {
            return true
        }

        return false
    }

    public func initNote(url: URL) -> Note? {
        guard let project = getProjectBy(url: url) else {
            return nil
        }

        let note = Note(url: url, with: project)

        return note
    }

    private func cleanTrash() {
        guard let trash = try? FileManager.default.url(for: .trashDirectory, in: .allDomainsMask, appropriateFor: UserDefaultsManagement.storageUrl, create: false) else {
            return
        }

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil, options: [])

            for fileURL in fileURLs {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            AppDelegate.trackError(error, context: "Storage.copyPins")
        }
    }

    public func saveCloudPins() {
    }

    public func restoreCloudPins() -> (removed: [Note]?, added: [Note]?) {
        return (nil, nil)
    }

    public func getPinned() -> [Note]? {
        noteList.filter(\.isPinned)
    }

    public func remove(project: Project) {
        if let index = projects.firstIndex(of: project) {
            projects.remove(at: index)
        }
    }

    public func getNotesBy(project: Project) -> [Note] {
        noteList.filter {
            $0.project == project
        }
    }

    public func loadProjects(from urls: [URL]) {
        var result = [URL]()
        for url in urls {
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
                result.append(url)
            } catch {
                AppDelegate.trackError(error, context: "Storage.enumerateNotes")
            }
        }

        let projects =
            result.compactMap {
                Project(url: $0)
            }

        guard !projects.isEmpty else {
            return
        }

        self.projects.removeAll()

        for project in projects {
            self.projects.append(project)
        }
    }

    public func trashItem(url: URL) -> URL? {
        guard let trashURL = Storage.sharedInstance().getDefaultTrash()?.url else {
            return nil
        }

        let fileName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension

        var destination = trashURL.appendingPathComponent(url.lastPathComponent)

        var i = 0

        while FileManager.default.fileExists(atPath: destination.path) {
            let nextName = "\(fileName)_\(i).\(fileExtension)"
            destination = trashURL.appendingPathComponent(nextName)
            i += 1
        }

        return destination
    }

    deinit {
        scopedStorageURL?.stopAccessingSecurityScopedResource()
    }
}

extension String: @retroactive Error {}
