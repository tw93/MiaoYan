import CMarkGFM
import Foundation

enum MobileHtmlRenderer {
    static func render(markdown: String, title: String?, fontSize: Int = 17) -> String {
        let body = markdownToHTML(markdown)
        let hero = heroTitleHTML(noteTitle: title, markdown: markdown)
        // Critical: the dynamic --font-size override MUST come after
        // bundledCSS, not before. mobile-reader.css declares its own default
        // `--font-size: 17px` on :root; same selector + same property means
        // whichever rule appears later wins. Putting the inline override
        // before bundledCSS silently lost the font-size selection — tap
        // Small/Medium/Large produced no visible change.
        return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5, user-scalable=yes">
            <meta name="theme-color" content="#f9f6f0" media="(prefers-color-scheme: light)">
            <meta name="theme-color" content="#121312" media="(prefers-color-scheme: dark)">
            <style>
            \(bundledCSS)
            :root { --font-size: \(fontSize)px; }
            </style>
            </head>
            <body>
            <main id="write" class="reader markdown-body heti">
            \(hero)\(body)
            </main>
            </body>
            </html>
            """
    }

    private static func markdownToHTML(_ markdown: String) -> String {
        _ = ensureExtensionsRegistered
        guard let parser = cmark_parser_new(CMARK_OPT_FOOTNOTES) else { return "" }
        defer { cmark_parser_free(parser) }

        for extName in ["table", "footnotes", "strikethrough", "tasklist"] {
            if let ext = cmark_find_syntax_extension(extName) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        cmark_parser_feed(parser, markdown, markdown.utf8.count)
        guard let node = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(node) }
        guard let cString = cmark_render_html(node, CMARK_OPT_UNSAFE | CMARK_OPT_HARDBREAKS, nil) else { return "" }
        let html = String(cString: cString)
        free(cString)
        return html
    }

    // MARK: - Hero title

    /// Decide whether to inject a large hero title at the top of the reader.
    /// Returns either an empty string or a `<h1 class="reader-title">…</h1>` block.
    ///
    /// Rules (see plan): only inject when we have a non-empty filename AND the
    /// document does not already begin with an H1. If the document opens with
    /// an H1 we always defer to the author, regardless of whether the H1 text
    /// matches the filename — same-text means redundant; different-text means
    /// the author is making an intentional editorial choice.
    private static func heroTitleHTML(noteTitle: String?, markdown: String) -> String {
        guard let raw = noteTitle else { return "" }
        let trimmedTitle = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return "" }

        if firstTopLevelH1Text(markdown) != nil {
            return ""
        }

        return "<h1 class=\"reader-title\">\(escapeHTML(trimmedTitle))</h1>\n"
    }

    /// Returns the text content of the first top-level H1 (`# X`) in the
    /// document, skipping a YAML-style frontmatter block at the very top.
    /// Returns nil when the first non-blank, non-frontmatter line is not an H1.
    /// `hasPrefix("# ")` already excludes `## `, `### `, etc., because those
    /// have `#` (not space) at index 1.
    private static func firstTopLevelH1Text(_ markdown: String) -> String? {
        let stripped = stripFrontmatter(markdown)
        for line in stripped.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard trimmed.hasPrefix("# ") else { return nil }
            let text = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    /// Strip a leading YAML-style frontmatter block (`---\n…\n---`).
    /// If the document doesn't start with `---` followed by a newline, return
    /// the original markdown unchanged — three dashes alone are a horizontal
    /// rule in CommonMark and we don't want to swallow them.
    private static func stripFrontmatter(_ markdown: String) -> Substring {
        guard markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n") else {
            return Substring(markdown)
        }
        let afterOpening = markdown.index(markdown.startIndex, offsetBy: markdown.hasPrefix("---\r\n") ? 5 : 4)
        guard let closingRange = markdown.range(of: "\n---", range: afterOpening..<markdown.endIndex) else {
            return Substring(markdown)
        }
        // Closing fence must be its own line: end-of-string or followed by \n
        let afterClose = markdown.index(closingRange.upperBound, offsetBy: 0)
        if afterClose == markdown.endIndex {
            return Substring("")
        }
        let nextChar = markdown[afterClose]
        guard nextChar == "\n" || nextChar == "\r" else {
            return Substring(markdown)
        }
        let bodyStart = markdown.index(after: afterClose)
        return markdown[bodyStart..<markdown.endIndex]
    }

    private static func escapeHTML(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out.append("&amp;")
            case "<": out.append("&lt;")
            case ">": out.append("&gt;")
            case "\"": out.append("&quot;")
            case "'": out.append("&#39;")
            default: out.append(ch)
            }
        }
        return out
    }

    private static let ensureExtensionsRegistered: Void = {
        cmark_gfm_core_extensions_ensure_registered()
    }()

    private static let bundledCSS = loadCSS()

    private static func loadCSS() -> String {
        guard let url = Bundle.main.url(forResource: "mobile-reader", withExtension: "css"),
            let css = try? String(contentsOf: url, encoding: .utf8)
        else {
            return fallbackCSS
        }
        return css
    }

    private static let fallbackCSS = """
        body {
            font-family: -apple-system, sans-serif;
            font-size: var(--font-size, 17px);
            line-height: 1.7;
            max-width: 680px;
            margin: 0 auto;
            padding: 20px;
            color: #262626;
            background: #f9f6f0;
        }
        @media (prefers-color-scheme: dark) {
            body { background: #121312; color: #e5e5ea; }
        }
        """
}
