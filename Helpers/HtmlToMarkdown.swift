import Foundation

/// Lightweight HTML to Markdown converter for pasteboard content, aimed at rich
/// text copied from browsers (AI chat answers, docs pages). Uses Foundation's
/// HTML-tidy parsing, no third-party dependency. Conversion is lossy by design:
/// unknown tags pass their children through, scripts and styles are dropped.
enum HtmlToMarkdown {

    /// Converts only when the HTML carries block structure worth keeping
    /// (headings, lists, tables, quotes, code blocks). Syntax-highlight HTML
    /// from code editors is span/div soup without those tags and returns nil,
    /// so plain-text paste stays authoritative for code.
    static func convertIfStructured(_ html: String) -> String? {
        guard containsBlockStructure(html) else { return nil }
        let markdown = convert(html)
        return markdown.isEmpty ? nil : markdown
    }

    static func containsBlockStructure(_ html: String) -> Bool {
        guard let regex = structureRegex else { return false }
        let range = NSRange(location: 0, length: (html as NSString).length)
        return regex.firstMatch(in: html, options: [], range: range) != nil
    }

    private static let structureRegex = try? NSRegularExpression(
        pattern: #"<(h[1-6]|table|ul|ol|blockquote|pre)[\s>]"#, options: [.caseInsensitive])

    static func convert(_ html: String) -> String {
        // Tidy ignores the HTML5 <meta charset> shorthand and defaults to Latin-1,
        // which mangles (Chrome clipboard) or drops (bare fragments) CJK text.
        // The pasteboard string is already decoded, so declaring UTF-8 is always correct.
        let declared = "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\">" + html
        guard let data = declared.data(using: .utf8),
            let document = try? XMLDocument(data: data, options: [.documentTidyHTML, .nodePreserveWhitespace])
        else {
            return ""
        }
        guard let root = document.rootElement() else { return "" }
        let body = descendant(named: "body", in: root) ?? root
        let markdown = renderBlockChildren(of: body)
        return collapseBlankLines(markdown).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tree helpers

    private static func descendant(named name: String, in node: XMLNode) -> XMLElement? {
        guard let element = node as? XMLElement else { return nil }
        if element.name?.lowercased() == name { return element }
        for child in element.children ?? [] {
            if let found = descendant(named: name, in: child) { return found }
        }
        return nil
    }

    private static let droppedTags: Set<String> = ["script", "style", "head", "meta", "link", "title", "svg", "button", "nav"]
    private static let blockTags: Set<String> = [
        "p", "div", "section", "article", "main", "header", "footer", "figure", "figcaption",
        "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "pre", "table", "hr", "details", "summary",
    ]

    // MARK: - Block rendering

    private static func renderBlockChildren(of node: XMLNode) -> String {
        var blocks: [String] = []
        var inlineRun = ""

        func flushInline() {
            let text = normalizeInlineWhitespace(inlineRun)
            // Tidy injects whitespace-only text nodes between block siblings;
            // they are formatting noise, not content.
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(text)
            }
            inlineRun = ""
        }

        for child in node.children ?? [] {
            let name = (child as? XMLElement)?.name?.lowercased()
            if let name, droppedTags.contains(name) { continue }
            if let name, blockTags.contains(name) {
                flushInline()
                let block = renderBlock(child as! XMLElement, name: name)
                if !block.isEmpty {
                    blocks.append(block)
                }
            } else {
                inlineRun += renderInline(child)
            }
        }
        flushInline()
        return blocks.joined(separator: "\n\n")
    }

    private static func renderBlock(_ element: XMLElement, name: String) -> String {
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(name.dropFirst())) ?? 1
            // A <br> inside a heading must not split the markdown heading line.
            let text = normalizeInlineWhitespace(renderInlineChildren(of: element))
                .replacingOccurrences(of: "\n", with: " ")
            return text.isEmpty ? "" : String(repeating: "#", count: level) + " " + text
        case "p", "summary", "figcaption":
            return normalizeInlineWhitespace(renderInlineChildren(of: element))
        case "hr":
            return "---"
        case "blockquote":
            let inner = renderBlockChildren(of: element)
            guard !inner.isEmpty else { return "" }
            return inner.components(separatedBy: "\n")
                .map { $0.isEmpty ? ">" : "> " + $0 }
                .joined(separator: "\n")
        case "pre":
            return renderPre(element)
        case "ul", "ol":
            return renderList(element, ordered: name == "ol")
        case "table":
            return renderTable(element)
        case "li":
            // A stray li without a parent list; render as unordered item.
            return "- " + normalizeInlineWhitespace(renderInlineChildren(of: element))
        default:
            // div/section/article and friends are transparent containers.
            return renderBlockChildren(of: element)
        }
    }

    private static func renderPre(_ element: XMLElement) -> String {
        var language = ""
        var codeHost: XMLElement = element
        if let code = (element.children ?? []).compactMap({ $0 as? XMLElement }).first(where: { $0.name?.lowercased() == "code" }) {
            codeHost = code
        }
        let classAttr = codeHost.attribute(forName: "class")?.stringValue ?? element.attribute(forName: "class")?.stringValue ?? ""
        for token in classAttr.components(separatedBy: .whitespaces) where token.hasPrefix("language-") {
            language = String(token.dropFirst("language-".count))
            break
        }
        let code = plainText(of: codeHost).trimmingCharacters(in: .newlines)
        var fence = "```"
        while code.contains(fence) {
            fence += "`"
        }
        return "\(fence)\(language)\n\(code)\n\(fence)"
    }

    private static func renderList(_ element: XMLElement, ordered: Bool, indent: String = "") -> String {
        var lines: [String] = []
        var counter = 1
        for child in element.children ?? [] {
            guard let item = child as? XMLElement, item.name?.lowercased() == "li" else { continue }
            let marker = ordered ? "\(counter). " : "- "
            counter += 1
            let childIndent = indent + String(repeating: " ", count: marker.count)

            // Emit pieces in document order: text after a code block must not
            // jump in front of it.
            var pieces: [(isBlock: Bool, text: String)] = []
            var inlineRun = ""
            func flushInline() {
                let text = normalizeInlineWhitespace(inlineRun)
                if !text.isEmpty { pieces.append((false, text)) }
                inlineRun = ""
            }

            for grand in item.children ?? [] {
                let grandName = (grand as? XMLElement)?.name?.lowercased()
                if let grandName, droppedTags.contains(grandName) { continue }
                if let grandName, grandName == "ul" || grandName == "ol" {
                    flushInline()
                    pieces.append((true, renderList(grand as! XMLElement, ordered: grandName == "ol", indent: childIndent)))
                } else if let grandName, grandName == "p" || grandName == "div" {
                    inlineRun += " " + renderInlineChildren(of: grand as! XMLElement)
                } else if let grandName, blockTags.contains(grandName) {
                    let block = renderBlock(grand as! XMLElement, name: grandName)
                    if !block.isEmpty {
                        flushInline()
                        pieces.append(
                            (true, block.components(separatedBy: "\n").map { childIndent + $0 }.joined(separator: "\n")))
                    }
                } else {
                    inlineRun += renderInline(grand)
                }
            }
            flushInline()

            if let first = pieces.first, !first.isBlock {
                lines.append(indent + marker + first.text)
                pieces.removeFirst()
            } else {
                lines.append(indent + String(marker.dropLast()))
            }
            for piece in pieces {
                if piece.isBlock {
                    lines.append(piece.text)
                } else {
                    lines.append(piece.text.components(separatedBy: "\n").map { childIndent + $0 }.joined(separator: "\n"))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func renderTable(_ element: XMLElement) -> String {
        var rows: [[String]] = []
        var headerCellCount = 0

        func collectRows(in node: XMLNode) {
            for child in node.children ?? [] {
                guard let childElement = child as? XMLElement, let name = childElement.name?.lowercased() else { continue }
                if name == "tr" {
                    var cells: [String] = []
                    var isHeader = false
                    for cell in childElement.children ?? [] {
                        guard let cellElement = cell as? XMLElement, let cellName = cellElement.name?.lowercased(),
                            cellName == "td" || cellName == "th"
                        else { continue }
                        if cellName == "th" { isHeader = true }
                        let text = normalizeInlineWhitespace(renderInlineChildren(of: cellElement))
                            .replacingOccurrences(of: "|", with: "\\|")
                            .replacingOccurrences(of: "\n", with: " ")
                        cells.append(text)
                    }
                    if !cells.isEmpty {
                        if isHeader, rows.isEmpty { headerCellCount = cells.count }
                        rows.append(cells)
                    }
                } else if name == "thead" || name == "tbody" || name == "tfoot" {
                    collectRows(in: childElement)
                }
            }
        }
        collectRows(in: element)

        guard !rows.isEmpty else { return "" }
        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return "" }

        // GFM needs a header row; when the table has none, the first row serves.
        if headerCellCount == 0 { headerCellCount = columnCount }

        var lines: [String] = []
        for (index, row) in rows.enumerated() {
            var cells = row
            while cells.count < columnCount { cells.append("") }
            lines.append("| " + cells.joined(separator: " | ") + " |")
            if index == 0 {
                lines.append("|" + Array(repeating: " --- |", count: columnCount).joined())
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Inline rendering

    private static func renderInlineChildren(of element: XMLElement) -> String {
        var result = ""
        for child in element.children ?? [] {
            result += renderInline(child)
        }
        return result
    }

    private static func renderInline(_ node: XMLNode) -> String {
        guard let element = node as? XMLElement else {
            return node.stringValue ?? ""
        }
        guard let name = element.name?.lowercased() else {
            return renderInlineChildren(of: element)
        }
        if droppedTags.contains(name) { return "" }

        switch name {
        case "br":
            // Sentinel for a hard break; soft newlines in text nodes collapse
            // to spaces, this survives normalizeInlineWhitespace as "\n".
            return "\u{2028}"
        case "strong", "b":
            let inner = normalizeInlineWhitespace(renderInlineChildren(of: element))
            return inner.isEmpty ? "" : "**\(inner)**"
        case "em", "i":
            let inner = normalizeInlineWhitespace(renderInlineChildren(of: element))
            return inner.isEmpty ? "" : "*\(inner)*"
        case "del", "s", "strike":
            let inner = normalizeInlineWhitespace(renderInlineChildren(of: element))
            return inner.isEmpty ? "" : "~~\(inner)~~"
        case "code", "kbd", "samp":
            let inner = plainText(of: element)
            guard !inner.isEmpty else { return "" }
            let delimiter = inner.contains("`") ? "``" : "`"
            // CommonMark: a code span starting/ending with a backtick needs
            // padding spaces, or the delimiters fuse with the content.
            let padded = inner.hasPrefix("`") || inner.hasSuffix("`") ? " \(inner) " : inner
            return "\(delimiter)\(padded)\(delimiter)"
        case "li":
            // Reached only in inline contexts (table cells); block contexts
            // route li through renderBlock. Space-separate the items.
            let inner = normalizeInlineWhitespace(renderInlineChildren(of: element))
            return inner.isEmpty ? "" : inner + " "
        case "a":
            let inner = normalizeInlineWhitespace(renderInlineChildren(of: element))
            let href = element.attribute(forName: "href")?.stringValue ?? ""
            if href.isEmpty || href.hasPrefix("#") { return inner }
            return inner.isEmpty ? href : "[\(inner)](\(href))"
        case "img":
            let src = element.attribute(forName: "src")?.stringValue ?? ""
            guard !src.isEmpty, !src.hasPrefix("data:") else { return "" }
            let alt = element.attribute(forName: "alt")?.stringValue ?? ""
            return "![\(alt)](\(src))"
        default:
            return renderInlineChildren(of: element)
        }
    }

    // MARK: - Text utilities

    private static func plainText(of node: XMLNode) -> String {
        return node.stringValue ?? ""
    }

    private static func normalizeInlineWhitespace(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for char in text {
            if char == "\u{2028}" {
                // <br> sentinel: hard break that absorbs surrounding soft whitespace.
                while result.hasSuffix(" ") { result.removeLast() }
                result.append("\n")
                pendingSpace = false
            } else if char.isWhitespace {
                pendingSpace = !result.isEmpty && !result.hasSuffix("\n")
            } else {
                if pendingSpace { result.append(" ") }
                pendingSpace = false
                result.append(char)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapseBlankLines(_ text: String) -> String {
        var lines: [String] = []
        var blankRun = 0
        var inFence = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
            }
            if !inFence, trimmed.isEmpty {
                blankRun += 1
                if blankRun == 1 { lines.append("") }
            } else {
                blankRun = 0
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }
}
