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
    private static let codeBlockRegex = try? NSRegularExpression(
        pattern: "```.*?```", options: [.dotMatchesLineSeparators])
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
    private static let tableSepRegex = try? NSRegularExpression(
        pattern: "^[\\|\\-:]+$", options: [.anchorsMatchLines])
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
        (text.hasPrefix("---\n") || text.hasPrefix("---\r\n")) && String(Frontmatter.body(of: text)) == text
    }

    /// Strip fenced code blocks (``` ... ```).
    static func stripCodeBlocks(_ input: String) -> String {
        guard let re = codeBlockRegex else { return input }
        let full = NSRange(location: 0, length: (input as NSString).length)
        return re.stringByReplacingMatches(in: input, range: full, withTemplate: "")
    }

    /// Strip Markdown line-start markers: `# `, `## `, `> `, `- `,
    /// `* `, `+ `, `1. ` etc. Keeps the text content.
    public static func stripMarkdownMarkers(_ input: String) -> String {
        var s = input
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

        return cardText(from: head)
    }

    /// A byte-limited read usually ends inside a multi-byte character, and a
    /// strict UTF-8 decode then fails, which sent the card to a full
    /// coordinated read of the file. Dropping the partial tail fixes that.
    static func decodeUTF8Prefix(_ data: Data) -> String? {
        for trim in 0...3 where trim < data.count || trim == 0 {
            if let text = String(data: data.dropLast(trim), encoding: .utf8) { return text }
        }
        return nil
    }

    public static func cardText(from head: String) -> String {
        var s = head
        s = String(Frontmatter.body(of: s))
        s = stripCodeBlocks(s)
        // Markers BEFORE noise: stripMarkdownMarkers uses ^ anchors that
        // need real newlines. stripNoise no longer collapses
        // whitespace, so newlines survive into this step.
        s = stripMarkdownMarkers(s)
        s = stripNoise(s)
        s = stripEmphasisMarkers(s)

        let lines = s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.prefix(2).joined(separator: " ")
    }
}
