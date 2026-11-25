import Foundation

/// How a file put into a note is named, linked and found again, the same on
/// the Mac and on the iPhone and iPad. Images go in an `i/` folder beside
/// the note, every other file in `files/`, both linked from the note's
/// folder (`/i/<name>`, `/files/<name>`), as the Mac has written them since
/// it first took dropped files.
public enum AttachmentFile {
    /// What a file is to a note: drawn in place, played in place, or linked.
    public enum Kind: Equatable, Sendable {
        case image, video, file
    }

    /// The folder beside the note that holds files of this kind.
    public static func folder(for kind: Kind) -> String {
        kind == .image ? "i" : "files"
    }

    /// Videos every reader plays in place: Safari and WebKit on macOS 12 and
    /// iOS 18 play these, and the iPhone's camera and Photos give `mov`.
    public static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    /// Images the readers draw from a note's own folder.
    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "svg", "avif", "tif", "tiff",
    ]

    public static func kind(ofExtension ext: String) -> Kind {
        let lower = ext.lowercased()
        if imageExtensions.contains(lower) { return .image }
        if videoExtensions.contains(lower) { return .video }
        return .file
    }

    /// The Mac's name for a file it takes in: letters, digits, `-` and `_`
    /// kept (Chinese is letters), every other run of characters one `-`, so
    /// the link needs no escaping. `合同 v2 (final).pdf` is `合同-v2-final.pdf`;
    /// a name with nothing left is a fresh UUID.
    public static func normalizedName(_ fileName: String, fallbackExtension: String) -> String {
        let url = URL(fileURLWithPath: fileName)
        let ext = url.pathExtension.isEmpty ? fallbackExtension : url.pathExtension
        let baseName = url.deletingPathExtension().lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

        var normalized = ""
        var lastWasSeparator = false
        for scalar in baseName.unicodeScalars {
            if allowed.contains(scalar) {
                normalized.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                normalized.append("-")
                lastWasSeparator = true
            }
        }
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        if normalized.isEmpty {
            normalized = UUID().uuidString.lowercased()
        }
        return ext.isEmpty ? normalized : "\(normalized).\(ext)"
    }

    /// The Markdown that puts the file at `path` (`/files/clip.mov`) in a
    /// note. An image or a video is written as an image, which the Mac
    /// editor draws inline and both readers show in place; any other file is
    /// a link named after the file as it was picked, so `合同 v2.pdf` reads
    /// as itself while its file is `合同-v2.pdf`.
    public static func markdown(path: String, kind: Kind, title: String) -> String {
        switch kind {
        case .image, .video:
            return "![](\(path))"
        case .file:
            var escaped = ""
            for character in title {
                if character == "[" || character == "]" || character == "\\" { escaped.append("\\") }
                escaped.append(character)
            }
            return "[\(escaped.isEmpty ? (path as NSString).lastPathComponent : escaped)](\(path))"
        }
    }

    /// The `i/` and `files/` names a note links (`![](/i/a.png)`,
    /// `[x](/files/b.pdf)`, `src="/files/c.mov"`), as written, each once.
    public static func references(in text: String) -> [(folder: String, name: String)] {
        guard let regex = referenceRegex else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        return regex.matches(in: text, range: range).compactMap { match in
            guard let folderRange = Range(match.range(at: 1), in: text),
                let nameRange = Range(match.range(at: 2), in: text)
            else { return nil }
            let folder = String(text[folderRange])
            let name = String(text[nameRange])
            return seen.insert(folder + "/" + name).inserted ? (folder, name) : nil
        }
    }

    private static let referenceRegex = try? NSRegularExpression(
        pattern: #"(?:\]\(\s*<?|src=["'])/(i|files)/([^)\s"'<>]+)"#)
}
