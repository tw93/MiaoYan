import Foundation

/// Clean Unused Attachments on the iPhone and iPad: the files in an `i/` or
/// `files/` folder that no note in the library links. Every directory is a
/// folder with its own `i/` and `files/`, links are read by
/// `AttachmentLinks` as the Mac reads them, notes in the library's `Trash`
/// keep their files by name, and anything that cannot be read cleans
/// nothing. The Mac's own scan is `Storage.findOrphanAttachments`, which
/// walks its registered folders the same way.
public enum UnusedAttachments {
    private static let attachmentFolderNames: Set<String> = ["i", "files"]
    private static let noteExtensions: Set<String> = ["md", "markdown", "txt"]

    /// What a scan found: the unused files, or why nothing may be cleaned.
    public enum Scan: Equatable, Sendable {
        case found([URL])
        /// A note or a folder could not be read: a note there could link
        /// any of the files.
        case unreadable
        /// A note iCloud keeps only online, or has not brought up to date;
        /// its download has started, so a later run can read it.
        case downloading
    }

    /// The files in the library at `root`'s `i/` and `files/` folders that
    /// no note links, or nil when a note or a folder could not be read and
    /// nothing may be cleaned: a note there could link any of them. A file
    /// changed since `cutoff` is never offered, as one just inserted may not
    /// have its link saved yet. `read` gives a note's text (the iPhone reads
    /// through a file coordinator).
    public static func find(
        in root: URL, changedBefore cutoff: Date,
        read: (URL) throws -> String = defaultRead
    ) -> [URL]? {
        if case .found(let files) = scan(in: root, changedBefore: cutoff, read: read) { return files }
        return nil
    }

    /// `find`, saying why nothing was found when nothing may be cleaned, so
    /// the iPhone can tell a note still downloading from one it cannot read.
    public static func scan(
        in root: URL, changedBefore cutoff: Date,
        read: (URL) throws -> String = defaultRead
    ) -> Scan {
        guard let listing = try? walk(root) else { return .unreadable }
        // With no i/ or files/ anywhere there is nothing to clean, and no
        // note needs reading: one only in iCloud must not turn "nothing
        // unused" into a failure.
        guard !listing.attachmentFolders.isEmpty else { return .found([]) }
        guard listing.onlyInICloud == nil else { return .downloading }

        let library = root.path
        var referenced = Set<String>()
        // A note in the Trash resolves its links against the Trash, so its
        // files are kept by name: a restore puts it back beside them.
        var trashNames = Set<String>()
        for (note, inTrash) in listing.notes {
            guard let text = try? read(note) else { return .unreadable }
            let directory = note.deletingLastPathComponent().path
            let paths = AttachmentLinks.paths(in: text, noteDirectory: directory, library: library)
            if inTrash {
                trashNames.formUnion(paths.map { ($0 as NSString).lastPathComponent })
                trashNames.formUnion(AttachmentLinks.links(in: text).map { ($0 as NSString).lastPathComponent })
            } else {
                referenced.formUnion(paths)
            }
        }
        // A note resolves against its folder as walked, an attachment folder
        // may have been reached another way (a symlink, /var against
        // /private/var), so both sides are compared resolved as well.
        let canonical = Set(referenced.map { ($0 as NSString).resolvingSymlinksInPath })

        var unused: [URL] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .creationDateKey, .contentModificationDateKey]
        for folder in listing.attachmentFolders {
            guard
                let enumerator = FileManager.default.enumerator(
                    at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            else { continue }
            for case let file as URL in enumerator {
                let values = try? file.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true || file.lastPathComponent.hasSuffix(".icloud") { continue }
                let lastChange = [values?.creationDate, values?.contentModificationDate].compactMap { $0 }.max()
                guard let lastChange, lastChange < cutoff else { continue }
                let path = file.path
                if referenced.contains(path) || canonical.contains((path as NSString).resolvingSymlinksInPath) { continue }
                if trashNames.contains(file.lastPathComponent) { continue }
                unused.append(file)
            }
        }
        return .found(unused)
    }

    /// A note's text as the Mac reads it: UTF-8, or the legacy readings
    /// `NoteText.decode` falls back to.
    public static func defaultRead(_ url: URL) throws -> String {
        guard let text = NoteText.decode(try Data(contentsOf: url)) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    private struct Listing {
        var notes: [(url: URL, inTrash: Bool)] = []
        var attachmentFolders: [URL] = []
        /// A note iCloud keeps only online, or has not brought up to date.
        var onlyInICloud: URL?
    }

    /// Every note below `root` at any depth, the Trash's included, and every
    /// `i/` and `files/` folder outside the Trash. Hidden, attachment and
    /// package folders are not entered for notes, and each real directory is
    /// entered once, so a linked folder is read through its target and a
    /// link back up the tree ends. Throws when a folder cannot be listed or
    /// a link's target is gone, since the notes there would go uncounted.
    private static func walk(_ root: URL) throws -> Listing {
        var listing = Listing()
        var walked = Set<String>()
        var pending: [(url: URL, inTrash: Bool)] = [(root, false)]
        // The Trash is walked first, as the Trash, so a link to it elsewhere
        // in the library finds it walked: reached through the link first,
        // its notes counted as live and its files lost their keep by name.
        let topLevel = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        for item in topLevel where item.lastPathComponent.caseInsensitiveCompare("Trash") == .orderedSame {
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { pending.append((item, true)) }
        }
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .ubiquitousItemDownloadingStatusKey,
        ]
        while let (directory, inTrash) = pending.popLast() {
            guard walked.insert(directory.resolvingSymlinksInPath().path).inserted else { continue }
            let items = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys, options: [])
            for item in items {
                let name = item.lastPathComponent
                if name.hasPrefix(".") {
                    // `.Note.md.icloud`: a note iCloud keeps only online. Its
                    // links cannot be read, so nothing is cleaned this time;
                    // every such note's download starts now, so the next run
                    // can read them all.
                    let inner = (String(name.dropFirst()) as NSString).deletingPathExtension
                    if (name as NSString).pathExtension == "icloud",
                        noteExtensions.contains((inner as NSString).pathExtension.lowercased())
                    {
                        try? FileManager.default.startDownloadingUbiquitousItem(at: item)
                        listing.onlyInICloud = listing.onlyInICloud ?? item
                    }
                    continue
                }
                var values = try item.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true {
                    let target = item.resolvingSymlinksInPath()
                    if target.path == item.path {
                        // A broken link to an image or other file is no folder.
                        let ext = item.pathExtension.lowercased()
                        if !ext.isEmpty, !noteExtensions.contains(ext) { continue }
                        throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: item.path])
                    }
                    values = try target.resourceValues(forKeys: Set(keys))
                }
                if values.isDirectory == true {
                    guard values.isPackage != true else { continue }
                    if attachmentFolderNames.contains(name) {
                        if !inTrash { listing.attachmentFolders.append(item) }
                    } else {
                        let isTrash = directory == root && name.caseInsensitiveCompare("Trash") == .orderedSame
                        pending.append((item, inTrash || isTrash))
                    }
                } else if noteExtensions.contains(item.pathExtension.lowercased()) {
                    // A note iCloud has downloaded but not brought up to
                    // date may lack a link the Mac just added; nothing is
                    // cleaned until it is current.
                    if let status = values.ubiquitousItemDownloadingStatus, status != .current {
                        try? FileManager.default.startDownloadingUbiquitousItem(at: item)
                        listing.onlyInICloud = listing.onlyInICloud ?? item
                    }
                    listing.notes.append((item, inTrash))
                }
            }
        }
        return listing
    }
}
