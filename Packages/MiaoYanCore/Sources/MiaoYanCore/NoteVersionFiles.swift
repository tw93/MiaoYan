import Foundation

/// How a device keeps the versions of its notes on its own disk, the same on
/// the Mac and the iPhone: one folder per note, named by the note's path,
/// holding plain text files named by the UTC second they were saved, the
/// newest `keptPerNote` of them, all notes together under `budget`.
/// Versions never sync; each device keeps what it saved.
public enum NoteVersionFiles {
    /// Every note's versions together stay under this: 20 versions of a few
    /// long notes, kept forever, otherwise grow without a ceiling (quiet-md
    /// keeps the same 200 MiB, 2026-11-21).
    public static let budget: Int64 = 200 << 20
    public static let keptPerNote = 20

    /// The folder a note's versions live in: its name, then a hash of its
    /// whole path, so two notes of one name in different folders keep
    /// apart.
    public static func folderName(for noteURL: URL) -> String {
        var hash: UInt64 = 5381
        for byte in noteURL.path.utf8 { hash = hash &* 31 &+ UInt64(byte) }
        return "\(noteURL.deletingPathExtension().lastPathComponent)-\(String(hash, radix: 16))"
    }

    /// The folder for a note on the iPhone and iPad, whose paths drift in
    /// three ways the Mac's do not, each of which would part a note from
    /// its history: iOS gives the app a new container path when it updates,
    /// so a note under `home` (the app's own Documents) is filed from it;
    /// a note's URL from the iCloud catalog and from a folder listing can
    /// differ by `/private`, dropped as text since a note's old path after
    /// a move no longer exists to resolve; and a note iCloud has not
    /// downloaded is listed as `.Name.md.icloud`, filed as `Name.md`.
    public static func folderName(for note: URL, home: String) -> String {
        func withoutPrivate(_ path: String) -> String {
            for alias in ["/private/var/", "/private/tmp/"] where path.hasPrefix(alias) {
                return String(path.dropFirst("/private".count))
            }
            return path
        }
        var note = note
        let name = note.lastPathComponent
        if name.hasPrefix("."), name.hasSuffix(".icloud"), name.count > ".icloud".count + 1 {
            note = note.deletingLastPathComponent()
                .appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
        }
        var path = withoutPrivate(note.standardizedFileURL.path)
        let home = withoutPrivate((home as NSString).standardizingPath)
        if path.hasPrefix(home + "/") { path = "/~" + path.dropFirst(home.count) }
        return folderName(for: URL(fileURLWithPath: path))
    }

    /// `2026-11-21T10-00-00Z.md`, the name a version saved at `date` gets.
    public static func fileName(for date: Date) -> String {
        formatter().string(from: date) + ".md"
    }

    public static func isVersionFileName(_ name: String) -> Bool {
        name.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z\.md$"#, options: .regularExpression) != nil
    }

    /// The versions in `folder`, newest first.
    public static func versions(in folder: URL) -> [(date: Date, url: URL)] {
        let fmt = formatter()
        return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .compactMap { url -> (Date, URL)? in
                guard let date = fmt.date(from: url.deletingPathExtension().lastPathComponent) else { return nil }
                return (date, url)
            }
            .sorted { $0.0 > $1.0 } ?? []
    }

    /// Two texts that differ only in blank lines and the spaces around each
    /// line are one version.
    public static func sameText(_ first: String, _ second: String) -> Bool {
        normalized(first) == normalized(second)
    }

    /// Writes `text` as `folder`'s newest version, unless it is the same text
    /// as the newest one already there; returns the file written, or nil
    /// when nothing was. A version merged in from a rename can already hold
    /// this second, so the save takes the next free one rather than writing
    /// over it. Keeps the newest `keptPerNote` afterwards.
    ///
    /// `exact` compares byte for byte, for the text a restore is about to
    /// replace: `sameText` ignores indentation and blank lines, which nest
    /// a list and part paragraphs, so a restore after an edit that only
    /// changed those kept no copy of it and the edit was gone.
    @discardableResult
    public static func save(_ text: String, in folder: URL, at date: Date = Date(), exact: Bool = false) throws -> URL? {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let latest = versions(in: folder).first,
            let previous = try? String(contentsOf: latest.url, encoding: .utf8),
            exact ? previous == text : sameText(previous, text)
        {
            return nil
        }
        var date = date
        var destination = folder.appendingPathComponent(fileName(for: date))
        while FileManager.default.fileExists(atPath: destination.path) {
            date.addTimeInterval(1)
            destination = folder.appendingPathComponent(fileName(for: date))
        }
        try text.write(to: destination, atomically: true, encoding: .utf8)
        prune(folder)
        return destination
    }

    /// Keeps the newest `keeping` versions; files that are no version
    /// (`.DS_Store`) are neither counted nor removed.
    public static func prune(_ folder: URL, keeping: Int = keptPerNote) {
        guard
            let all = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter({ isVersionFileName($0.lastPathComponent) }),
            all.count > keeping
        else { return }
        all.sorted { $0.lastPathComponent > $1.lastPathComponent }
            .dropFirst(keeping)
            .forEach { try? FileManager.default.removeItem(at: $0) }
    }

    /// Removes the oldest versions across all notes once the history passes
    /// `budget`, down to nine tenths of it, never a note's newest one, so
    /// each note keeps the version it can always go back to. Trimmed only to
    /// the budget, the next save passed it again and every save after it
    /// walked the whole history. Version files are named by their UTC time,
    /// so names sort oldest first in every folder alike. Returns the size
    /// left.
    @discardableResult
    public static func keepWithinBudget(root: URL, budget: Int64) -> Int64 {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let folders = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        var removable: [(url: URL, size: Int64)] = []
        // Only real folders and files named as a version are counted or
        // removed: a symlink, a .DS_Store or anything else left in the folder
        // is neither, and must not pass for a note's newest version.
        for folder in folders {
            let folderValues = try? folder.resourceValues(forKeys: Set(keys))
            guard folderValues?.isDirectory == true, folderValues?.isSymbolicLink != true else { continue }
            let files = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
            let versions = files.filter { file in
                let values = try? file.resourceValues(forKeys: Set(keys))
                return values?.isRegularFile == true && values?.isSymbolicLink != true && isVersionFileName(file.lastPathComponent)
            }
            let newestFirst = versions.sorted { $0.lastPathComponent > $1.lastPathComponent }
            for (index, file) in newestFirst.enumerated() {
                let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                total += size
                if index > 0 { removable.append((file, size)) }
            }
        }
        guard total > budget else { return total }
        let target = budget / 10 * 9
        for file in removable.sorted(by: { $0.url.lastPathComponent < $1.url.lastPathComponent }) {
            guard total > target else { break }
            if (try? manager.removeItem(at: file.url)) != nil { total -= file.size }
        }
        return total
    }

    /// Moves one version into `folder`. Two saves in the same second share
    /// a name: the same bytes there make this copy a duplicate, which goes;
    /// other bytes move under the next free second, so the name still
    /// reads as a version and the history keeps its order.
    public static func merge(version file: URL, into folder: URL) throws {
        let manager = FileManager.default
        var destination = folder.appendingPathComponent(file.lastPathComponent)
        if manager.fileExists(atPath: destination.path) {
            if manager.contentsEqual(atPath: file.path, andPath: destination.path) {
                try manager.removeItem(at: file)
                return
            }
            guard var date = formatter().date(from: file.deletingPathExtension().lastPathComponent) else {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destination.path])
            }
            repeat {
                date.addTimeInterval(1)
                destination = folder.appendingPathComponent(fileName(for: date))
            } while manager.fileExists(atPath: destination.path)
        }
        try manager.moveItem(at: file, to: destination)
    }

    private static func formatter() -> DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }

    private static func normalized(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
