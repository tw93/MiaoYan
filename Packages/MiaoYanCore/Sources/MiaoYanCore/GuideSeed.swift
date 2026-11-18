import Foundation

/// The guide a new library starts with: one folder of sample notes the Mac
/// and the iPhone app both copy from the same bundled files, so whichever
/// device opens the library first writes it and the other finds it there.
public enum GuideSeed {
    /// Every name the guide folder can have, in any language it was seeded
    /// in. A library holding any of them already has its guide.
    public static let folderNames = ["妙言指南", "MiaoYan Guide"]

    public struct Plan: Equatable, Sendable {
        public let folder: String
        /// File names in the bundle's `Initial` folder, the first one the
        /// note a new library opens on.
        public let notes: [String]
    }

    /// The Chinese guide for any Chinese language tag, the English one for
    /// every other language.
    public static func plan(forLanguage language: String) -> Plan {
        if language.hasPrefix("zh") {
            return Plan(folder: "妙言指南", notes: ["介绍妙言.md", "妙言 Markdown 语法指南.md", "妙言 PPT.md"])
        }
        return Plan(folder: "MiaoYan Guide", notes: ["Introduction to MiaoYan.md", "MiaoYan Markdown Syntax Guide.md", "MiaoYan PPT.md"])
    }

    /// Whether this device should write the guide now. Only into a library
    /// with no note and no guide folder, and only once per device, so a
    /// guide the user put away does not grow back, and a library the other
    /// device already filled gets nothing more.
    public static func shouldSeed(libraryHasNotes: Bool, guideFolderExists: Bool, seededOnThisDevice: Bool) -> Bool {
        !libraryHasNotes && !guideFolderExists && !seededOnThisDevice
    }

    /// Whether a folder name is a guide's: one of `folderNames`, or one
    /// with the number iCloud adds when two devices wrote it before either
    /// had synced (`MiaoYan Guide 2`).
    public static func isGuideFolderName(_ name: String) -> Bool {
        folderNames.contains { base in
            guard name.hasPrefix(base) else { return false }
            let rest = name.dropFirst(base.count)
            return rest.isEmpty || (rest.first == " " && rest.dropFirst().allSatisfy(\.isNumber) && rest.count > 1)
        }
    }

    /// Whether `url` is a guide folder directly inside the library root.
    /// Paths are compared resolved, since a library can be registered under
    /// /tmp while its folders come in under /private/tmp.
    public static func isGuideFolder(_ url: URL, root: URL) -> Bool {
        let resolved = { (url: URL) in url.resolvingSymlinksInPath().standardizedFileURL.path }
        return isGuideFolderName(url.lastPathComponent) && resolved(url.deletingLastPathComponent()) == resolved(root)
    }

    /// Whether the library root already holds a guide folder on disk.
    public static func guideFolderExists(in root: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.contains(where: isGuideFolderName)
    }

    /// Whether any note file sits anywhere under `root`, the Trash included,
    /// stopping at the first. An iCloud note not downloaded to this device
    /// is a hidden `.Name.md.icloud` file on older systems and still counts:
    /// a library whose notes all live in the cloud is not empty.
    public static func libraryHasNotes(at root: URL, extensions: [String]) -> Bool {
        let wanted = Set(extensions.map { $0.lowercased() })
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants])
        else { return false }
        for case let url as URL in walker {
            var name = url.lastPathComponent
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                if name.hasPrefix(".") { walker.skipDescendants() }
                continue
            }
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(".icloud".count))
            }
            if wanted.contains((name as NSString).pathExtension.lowercased()) { return true }
        }
        return false
    }

    /// The link at the end of the introduction that puts the guide away.
    public static let hideLink = "miaoyan://guide/hide"

    /// Whether `url` is the link that puts the guide away.
    public static func isHideLink(_ url: URL) -> Bool {
        url.scheme == "miaoyan" && url.host == "guide" && url.path == "/hide"
    }
}
