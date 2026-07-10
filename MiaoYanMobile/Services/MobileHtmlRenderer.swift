import CMarkGFM
import Foundation

enum MobileHtmlRenderer {
    static func render(
        markdown: String,
        title: String?,
        fontSize: Int = 17,
        fontCSS: String? = nil,
        assetRoot: URL? = nil
    ) -> String {
        let body = rewriteWikilinks(
            in: rewriteLocalAssetPaths(in: markdownToHTML(markdown), assetRoot: assetRoot))
        let hero = heroTitleHTML(noteTitle: title, markdown: markdown)
        let scripts = readerScripts(for: body)
        // Critical: the dynamic --font-size / --font overrides MUST come
        // after bundledCSS, not before. mobile-reader.css declares its own
        // defaults on :root; same selector + same property means whichever
        // rule appears later wins. Putting the inline override before
        // bundledCSS silently lost the font-size selection — tap
        // Small/Medium/Large produced no visible change.
        let fontOverride = fontCSS.map { ":root { --font: \($0); --heading-font: \($0); }" } ?? ""
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
            \(fontOverride)
            </style>
            </head>
            <body>
            <main id="write" class="reader markdown-body heti">
            \(hero)\(body)
            </main>
            \(scripts)
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

    // MARK: - Local asset rewriting

    private static let imgSrcRegex = try? NSRegularExpression(
        pattern: "(<img[^>]*?\\ssrc=\")([^\"]+)(\")", options: [.caseInsensitive])

    /// Rewrite local image references to the custom `miaoyan-asset` scheme.
    /// The reader loads via `loadHTMLString`, which grants no local-file
    /// read access, so `file://`-relative images never render; the scheme
    /// handler (`LocalAssetSchemeHandler`) serves them from disk instead.
    ///
    /// Path semantics mirror the macOS app (`Note.getImageUrl`): `/i/...`
    /// and plain relative paths both resolve against the note's folder.
    private static func rewriteLocalAssetPaths(in html: String, assetRoot: URL?) -> String {
        guard let assetRoot, let regex = imgSrcRegex, html.contains("<img") else { return html }
        let mutable = NSMutableString(string: html)
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: mutable.length))
        for match in matches.reversed() where match.numberOfRanges == 4 {
            let src = mutable.substring(with: match.range(at: 2))
            guard let rewritten = LocalAssetURL.absoluteString(forMarkdownSrc: src, noteFolder: assetRoot)
            else { continue }
            mutable.replaceCharacters(in: match.range(at: 2), with: rewritten)
        }
        return mutable as String
    }

    // MARK: - Wikilinks

    private static let wikilinkPattern = try? NSRegularExpression(
        pattern: "\\[\\[([^\\[\\]|]+)(?:\\|([^\\[\\]]+))?\\]\\]")
    private static let codeRegionPattern = try? NSRegularExpression(
        pattern: "<pre[\\s\\S]*?</pre>|<code[\\s\\S]*?</code>", options: [.caseInsensitive])

    /// Rewrite `[[target]]` / `[[target|label]]` into anchors on the
    /// `miaoyan-wiki` scheme so the reader can navigate between notes.
    /// cmark leaves wikilinks as literal text, so this runs on the HTML —
    /// skipping `<pre>`/`<code>` regions where the syntax must stay verbatim.
    private static func rewriteWikilinks(in html: String) -> String {
        guard html.contains("[["), let codeRegex = codeRegionPattern else { return html }
        let source = html as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let codeRanges = codeRegex.matches(in: html, range: fullRange).map(\.range)

        var result = ""
        result.reserveCapacity(html.count)
        var cursor = 0
        for codeRange in codeRanges {
            if codeRange.location > cursor {
                let prose = source.substring(
                    with: NSRange(location: cursor, length: codeRange.location - cursor))
                result += rewriteWikilinkSegment(prose)
            }
            result += source.substring(with: codeRange)
            cursor = codeRange.location + codeRange.length
        }
        if cursor < source.length {
            let prose = source.substring(with: NSRange(location: cursor, length: source.length - cursor))
            result += rewriteWikilinkSegment(prose)
        }
        return result
    }

    private static func rewriteWikilinkSegment(_ segment: String) -> String {
        guard segment.contains("[["), let regex = wikilinkPattern else { return segment }
        let mutable = NSMutableString(string: segment)
        let matches = regex.matches(in: segment, range: NSRange(location: 0, length: mutable.length))
        for match in matches.reversed() {
            let rawTarget = mutable.substring(with: match.range(at: 1))
            let label =
                match.range(at: 2).location != NSNotFound
                ? mutable.substring(with: match.range(at: 2))
                : rawTarget
            // cmark already entity-escaped this text; decode before building
            // the URL so the resolver sees the real title.
            let target = unescapeHTML(rawTarget).trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty,
                let href = WikilinkURL.absoluteString(forTitle: target)
            else { continue }
            // `label` stays as-is: it is already HTML-escaped output.
            mutable.replaceCharacters(
                in: match.range,
                with: "<a class=\"wikilink\" href=\"\(escapeHTML(href))\">\(label)</a>")
        }
        return mutable as String
    }

    private static func unescapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: - Reader scripts

    /// Conditionally reference the bundled scripts a note actually needs.
    /// Scripts load through the `miaoyan-bundle` scheme handler, so the
    /// rendered HTML string (and the reader's HTML cache) stays small.
    private static func readerScripts(for body: String) -> String {
        let hasCodeBlock = body.contains("<pre><code")
        let hasMermaid = body.contains("language-mermaid")
        var out = ""
        if hasMermaid {
            // Convert mermaid fences to divs BEFORE hljs runs, then let
            // mermaid pick its theme from the current appearance. The HTML
            // is cached independent of appearance, so the theme decision
            // must happen in the page at load time, not at render time.
            out += """
                <script src="miaoyan-bundle:///mermaid.min.js"></script>
                <script>
                document.querySelectorAll("pre code.language-mermaid").forEach(function (code) {
                  var div = document.createElement("div");
                  div.className = "mermaid";
                  div.textContent = code.textContent;
                  code.closest("pre").replaceWith(div);
                });
                var miaoyanDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
                mermaid.initialize({ startOnLoad: true, theme: miaoyanDark ? "dark" : "neutral" });
                </script>
                """
        }
        if hasCodeBlock {
            out += """
                <script src="miaoyan-bundle:///highlight.min.js"></script>
                <script>
                document.querySelectorAll("pre code").forEach(function (el) {
                  if (el.classList.contains("language-mermaid")) { return; }
                  hljs.highlightElement(el);
                });
                </script>
                """
        }
        return out
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
