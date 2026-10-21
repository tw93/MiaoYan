import Foundation

/// The plain-text preview of a note that list rows and cards show: the
/// opening prose with frontmatter, code, Markdown markers and link targets
/// removed. Moved from the iPhone app so the Mac list uses the same rules.
public enum NotePreview {
    public static let byteLimit = 900
    static let frontmatterLimit = 16 * 1024

    /// Pre-compiled regexes for `stripNoise`. Compiling per-call
    /// would dominate CPU for a 1500-note search.
    private static let htmlTagRegex = try? NSRegularExpression(
        pattern: "<[^>]+>", options: [])
    private static let mdImageRegex = try? NSRegularExpression(
        pattern: "!\\[[^\\]]*\\]\\([^)]*\\)", options: [])
    private static let mdLinkRegex = try? NSRegularExpression(
        pattern: "\\[([^\\]]*)\\]\\([^)]*\\)", options: [])
    private static let bareUrlRegex = try? NSRegularExpression(
        pattern: "https?://\\S+", options: [])
    private static let inlineCodeRegex = try? NSRegularExpression(
        pattern: "`([^`]+)`", options: [])
    /// A fence the read stopped before closing runs to the end.
    private static let codeBlockRegex = try? NSRegularExpression(
        pattern: "```.*?(?:```|\\z)", options: [.dotMatchesLineSeparators])
    /// Fence lines alone, for snippets that keep the code a search hit.
    private static let fenceLineRegex = try? NSRegularExpression(
        pattern: "^[ \\t]*(?:```|~~~)[^\\n]*$", options: [.anchorsMatchLines])
    /// A slide deck's settings comment; one never closed loses only its
    /// opening line, so a search hit after it still shows.
    private static let htmlCommentRegex = try? NSRegularExpression(
        pattern: "<!--(?:.*?-->|[^\\n]*)", options: [.dotMatchesLineSeparators])
    private static let mdMarkerRegex = try? NSRegularExpression(
        pattern: "^[#>*+\\-]+\\s*", options: [.anchorsMatchLines])
    private static let mdOrderedListRegex = try? NSRegularExpression(
        pattern: "^\\d+[\\.\\)、]\\s*", options: [.anchorsMatchLines])
    /// `**` and `__` first (greedy), then single `*` and `_`, then `~~`.
    /// Order matters: `**` must be consumed before `*`.
    private static let emphasisRegex = try? NSRegularExpression(
        pattern: "\\*\\*|__|~~|[*_]", options: [])
    private static let checkboxRegex = try? NSRegularExpression(
        pattern: "\\[[ xX]\\]\\s*", options: [])
    private static let wikilinkRegex = try? NSRegularExpression(
        pattern: "\\[\\[(?:[^\\]|]*\\|)?([^\\]]*)\\]\\]", options: [])
    /// `|---|`, `| --- | :---: |` and the like.
    private static let tableSepRegex = try? NSRegularExpression(
        pattern: "^(?=[^\\n]*-)(?=[^\\n]*\\|)[ \\t|:\\-]+$", options: [.anchorsMatchLines])
    private static let tablePipeRegex = try? NSRegularExpression(
        pattern: "\\|", options: [])
    private static let hrUnderscoreRegex = try? NSRegularExpression(
        pattern: "^_{3,}$", options: [.anchorsMatchLines])
    private static let htmlEntityRegex = try? NSRegularExpression(
        pattern: "&[a-zA-Z]+;|&#\\d+;", options: [])

    /// Remove HTML tags and Markdown noise (raw image syntax, link URLs,
    /// bare URLs, inline-code backticks) so card previews and search
    /// snippets read like prose instead of source. Markdown link text is
    /// preserved (`[label](url)` → `label`); inline-code text is
    /// preserved minus the backticks. Whitespace runs collapse to a
    /// single space at the end.
    ///
    /// Used by `text(at:)` (list rows and iPhone cards) and the iPhone
    /// search snippet so both surfaces share the same cleanup rules.
    public static func stripNoise(_ input: String) -> String {
        var s = input
        let full = { (str: String) in NSRange(location: 0, length: (str as NSString).length) }
        s = stripComments(s)
        if let re = fenceLineRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "")
        }
        if let re = htmlTagRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "")
        }
        if let re = htmlEntityRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "")
        }
        if let re = wikilinkRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "$1")
        }
        if let re = checkboxRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "")
        }
        if let re = tableSepRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "")
        }
        if let re = tablePipeRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: " ")
        }
        if let re = hrUnderscoreRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "")
        }
        if let re = mdImageRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "")
        }
        if let re = mdLinkRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "$1")
        }
        if let re = bareUrlRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "")
        }
        if let re = inlineCodeRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "$1")
        }
        // Whitespace collapse is intentionally NOT done here, newlines
        // must survive so downstream stripMarkdownMarkers can anchor
        // `^` to real line starts. Callers that need single-line output
        // collapse whitespace after the full pipeline finishes.
        return s
    }

    /// True when the text opens a frontmatter block that the text does not
    /// close, as happens when a card reads only the first bytes of a note.
    static func hasOpenFrontmatter(_ text: String) -> Bool {
        Frontmatter.opensUnclosedBlock(text)
    }

    /// Remove the first non-empty line when it is a level-one heading whose
    /// text matches `title`.
    static func dropRepeatedTitle(_ input: String, title: String) -> String {
        let want = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !want.isEmpty else { return input }
        var lines = input.components(separatedBy: "\n")
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return input
        }
        let line = lines[first].trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("# ") else { return input }
        var heading = String(line.dropFirst(2))
        while heading.hasSuffix("#") { heading.removeLast() }
        heading = stripEmphasisMarkers(stripNoise(heading)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard heading == want else { return input }
        lines.remove(at: first)
        return lines.joined(separator: "\n")
    }

    /// Strip fenced code blocks (``` ... ```).
    static func stripCodeBlocks(_ input: String) -> String {
        guard let re = codeBlockRegex else { return input }
        let full = NSRange(location: 0, length: (input as NSString).length)
        return re.stringByReplacingMatches(in: input, range: full, withTemplate: "")
    }

    /// Runs before the line markers, which would eat a comment's `-->`.
    static func stripComments(_ input: String) -> String {
        guard let re = htmlCommentRegex else { return input }
        return re.stringByReplacingMatches(in: input, range: NSRange(location: 0, length: (input as NSString).length), withTemplate: "")
    }

    /// Strip Markdown line-start markers: `# `, `## `, `> `, `- `,
    /// `* `, `+ `, `1. ` etc. Keeps the text content.
    public static func stripMarkdownMarkers(_ input: String) -> String {
        var s = stripComments(input)
        let full = { (str: String) in NSRange(location: 0, length: (str as NSString).length) }
        if let re = mdMarkerRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "")
        }
        if let re = mdOrderedListRegex {
            s = re.stringByReplacingMatches(in: s, range: full(s), withTemplate: "")
        }
        return s
    }

    /// Strip bold/italic/strikethrough markers (`**`, `*`, `__`, `_`, `~~`).
    public static func stripEmphasisMarkers(_ input: String) -> String {
        guard let re = emphasisRegex else { return input }
        let full = NSRange(location: 0, length: (input as NSString).length)
        return re.stringByReplacingMatches(in: input, range: full, withTemplate: "")
    }

    /// Pure regex-pipeline preview: strip every non-prose element, then
    /// take the first two content lines after the title. No line-level
    /// if/else logic, just successive regex passes that delete
    /// structural markup and leave clean text.
    ///
    /// The card text, or nil when the file could not be read here (an iCloud
    /// placeholder), which is the only case worth a coordinated full read.
    public static func text(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: byteLimit),
            var head = decodeUTF8Prefix(data)
        else { return nil }
        // Long frontmatter runs past the first bytes; read on to its end
        // rather than showing its keys as the preview.
        if hasOpenFrontmatter(head),
            let more = try? handle.read(upToCount: frontmatterLimit),
            let rest = decodeUTF8Prefix(data + more)
        {
            head = rest
        }
        if hasOpenFrontmatter(head) { return "" }

        return cardText(from: head, title: url.deletingPathExtension().lastPathComponent)
    }

    /// A byte-limited read usually ends inside a multi-byte character, and a
    /// strict UTF-8 decode then fails, which sent the card to a full
    /// coordinated read of the file. Dropping the partial tail fixes that.
    /// Notes in other encodings (GBK, Big5, UTF-16) go through the same
    /// decoder as a full read; UTF-8 alone left their cards blank.
    static func decodeUTF8Prefix(_ data: Data) -> String? {
        for trim in 0...3 where trim < data.count || trim == 0 {
            if let text = String(data: data.dropLast(trim), encoding: .utf8) { return text }
        }
        for trim in 0...3 where trim < data.count || trim == 0 {
            if let text = NoteText.decode(data.dropLast(trim)) { return text }
        }
        return nil
    }

    /// `title` is the note's name as the row or card already prints it. An
    /// opening `# heading` that only repeats it is dropped, or the card read
    /// "发布流程 发布流程 打包"; a heading that says something else stays.
    public static func cardText(from head: String, title: String? = nil) -> String {
        var s = head
        s = String(Frontmatter.body(of: s))
        s = stripCodeBlocks(s)
        if let title { s = dropRepeatedTitle(s, title: title) }
        // Markers BEFORE noise: stripMarkdownMarkers uses ^ anchors that
        // need real newlines. stripNoise no longer collapses
        // whitespace, so newlines survive into this step.
        s = stripMarkdownMarkers(s)
        s = stripNoise(s)
        s = stripEmphasisMarkers(s)

        // Table cells part by the spaces their pipes left behind.
        let lines = s.components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
            .filter { !$0.isEmpty }
        return lines.prefix(2).joined(separator: " ")
    }
}
