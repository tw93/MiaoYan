import Foundation

/// Which attachment files a note's text links, read the same way on the Mac
/// and the iPhone, so Clean Unused Attachments keeps the same files on both.
/// Text only, so a scan can run it off the main actor.
public enum AttachmentLinks {
    /// Every attachment link in `text`, in each form `variants` gives,
    /// once: the two patterns find the same `src` value, and a note repeats
    /// its links. A link target is read whole where the text marks its
    /// ends: a `<…>` destination, which may hold spaces
    /// (`![](<i/my photo.png>)`), a quoted `src` or `href` value
    /// (`<img src="i/my photo.png">`), and a `](…)` with balanced
    /// parentheses. Elsewhere `attachmentPathRegex` stops at a space or an
    /// angle bracket. Cut at the space (`i/my`), or keeping the closing
    /// `>`, the link named no file, and Clean Unused Attachments offered an
    /// image the preview still showed. Extra entries only keep files, so
    /// anything unsure is included.
    public static func links(in text: String) -> Set<String> {
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        var raw = Set<String>()
        attachmentPathRegex.enumerateMatches(in: text, options: [], range: range) { result, _, _ in
            guard let match = result?.range else { return }
            raw.insert(nsString.substring(with: match))
        }
        wholeLinkTargetRegex.enumerateMatches(in: text, options: [], range: range) { result, _, _ in
            guard let result else { return }
            for group in 1..<result.numberOfRanges where result.range(at: group).location != NSNotFound {
                let target = nsString.substring(with: result.range(at: group)).trimmingCharacters(in: .whitespaces)
                if !target.isEmpty, !target.contains("://"), !target.hasPrefix("data:") { raw.insert(target) }
            }
        }
        var links = Set<String>()
        for link in raw {
            links.formUnion(variants(link))
        }
        return links
    }

    /// The forms a link as written may name its file by: itself, percent
    /// decoded, with Markdown's backslash escapes removed (`i/a\_b.png`),
    /// and cut at the first `#` or `?`, since a query or fragment
    /// (`files/spec.pdf#page=3`, `i/a.png?v=2`) is no part of the name.
    public static func variants(_ raw: String) -> Set<String> {
        var variants: Set<String> = [raw]
        if let decoded = raw.removingPercentEncoding { variants.insert(decoded) }
        for variant in variants where variant.contains("\\") {
            variants.insert(removingBackslashEscapes(variant))
        }
        for variant in variants {
            if let cut = variant.firstIndex(where: { $0 == "#" || $0 == "?" }), cut != variant.startIndex {
                variants.insert(String(variant[..<cut]))
            }
        }
        return variants
    }

    /// The absolute path `link` names for a note in `noteDirectory`, whose
    /// folder (the one holding its `i/` and `files/`) is `folder`, inside the
    /// library at `library`; nil when it leaves its bound. `/i/a.png` and
    /// `i/a.png` resolve against the folder and must stay in it; anything
    /// else resolves against the note's own directory and must stay in the
    /// library: a note in a subfolder reaches a parent folder's `i/` or
    /// `files/` with `../`, and bounded by its folder, Clean Unused
    /// Attachments trashed those files.
    public static func resolve(_ link: String, folder: String, noteDirectory: String, library: String) -> String? {
        guard !link.isEmpty else { return nil }

        if link.hasPrefix("/") {
            let resolved = NSString(string: folder + link).standardizingPath
            guard resolved.hasPrefix(folder) else { return nil }
            return resolved
        }

        var path = link
        if path.hasPrefix("./") {
            path = String(path.dropFirst(2))
        }

        if path.hasPrefix("i/") || path.hasPrefix("files/") {
            let resolved = NSString(string: folder + "/" + path).standardizingPath
            guard resolved.hasPrefix(folder) else { return nil }
            return resolved
        }

        let relative = NSString(string: noteDirectory).appendingPathComponent(path)
        let standardized = NSString(string: relative).standardizingPath
        guard standardized.hasPrefix(library.hasSuffix("/") ? library : library + "/") else { return nil }
        return standardized
    }

    /// Every absolute path the links in `text` name, for a note in
    /// `noteDirectory` whose folder is that same directory, as every folder
    /// keeps its own `i/` and `files/`.
    public static func paths(in text: String, noteDirectory: String, library: String) -> Set<String> {
        Set(links(in: text).compactMap { resolve($0, folder: noteDirectory, noteDirectory: noteDirectory, library: library) })
    }

    /// A backslash before ASCII punctuation is Markdown's escape for it.
    private static func removingBackslashEscapes(_ text: String) -> String {
        var result = ""
        var escaping = false
        for character in text {
            if escaping {
                if !(character.isASCII && (character.isPunctuation || character.isSymbol)) { result.append("\\") }
                result.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        if escaping { result.append("\\") }
        return result
    }

    /// `](<target>)`, a reference definition `]: <target>`, a quoted
    /// `src`/`href` value, an unquoted one up to a space or `>`, and a plain
    /// `](target)` or `]: target` with balanced parentheses
    /// (`files/report(1).pdf`, `files/Tom's.pdf`), which ends at a space
    /// before a title; the target is whichever group matched.
    private static let wholeLinkTargetRegex: NSRegularExpression = {
        let pattern =
            #"\]\(\s*<([^<>\n]+)>|\]:[ \t]*<([^<>\n]+)>|\b(?:src|href)\s*=\s*(?:"([^"\n]*)"|'([^'\n]*)'|([^\s"'>][^\s">]*))|\](?:\(\s*|:[ \t]*)(?!<)((?:[^()\s]|\([^()\s]*\))+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            preconditionFailure("AttachmentLinks.wholeLinkTargetRegex literal is invalid: \(pattern)")
        }
        return regex
    }()

    private static let attachmentPathRegex: NSRegularExpression = {
        let pattern = #"(?:(?:\.\./|\./|/)*)(?:i|files)/[^)\s'"<>]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            preconditionFailure("AttachmentLinks.attachmentPathRegex literal is invalid: \(pattern)")
        }
        return regex
    }()
}
