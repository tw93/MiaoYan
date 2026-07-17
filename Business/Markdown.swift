import CMarkGFM
import Foundation

extension String {
    func matches(_ pattern: String) -> Bool {
        return self.range(of: pattern, options: .regularExpression) != nil
    }
}

func renderMarkdownHTML(markdown: String, useGithubLineBreak: Bool) -> String? {
    cmark_gfm_core_extensions_ensure_registered()

    guard let parser = cmark_parser_new(CMARK_OPT_FOOTNOTES) else { return nil }
    defer { cmark_parser_free(parser) }

    let extensions = ["table", "footnotes", "strikethrough", "tasklist"]
    for extName in extensions {
        if let ext = cmark_find_syntax_extension(extName) {
            cmark_parser_attach_syntax_extension(parser, ext)
        }
    }

    cmark_parser_feed(parser, markdown, markdown.utf8.count)
    guard let node = cmark_parser_finish(parser) else { return nil }

    var res: String
    if useGithubLineBreak {
        res = String(cString: cmark_render_html(node, CMARK_OPT_UNSAFE | CMARK_OPT_NOBREAKS | CMARK_OPT_SOURCEPOS, nil))
    } else {
        res = String(cString: cmark_render_html(node, CMARK_OPT_UNSAFE | CMARK_OPT_HARDBREAKS | CMARK_OPT_SOURCEPOS, nil))
    }

    // Match <p> with or without data-sourcepos attribute, capture both to preserve the attrs.
    let pattern = #"(<p\b[^>]*>)(\$\$[\s\S]*?\$\$)<\/p>"#
    let regex = try? NSRegularExpression(pattern: pattern, options: [])
    let nsRes = res as NSString
    var newRes = res
    regex?.enumerateMatches(in: res, options: [], range: NSRange(location: 0, length: nsRes.length)) { match, _, _ in
        guard let match = match else { return }
        let openTag = nsRes.substring(with: match.range(at: 1))
        let formulaBlock = nsRes.substring(with: match.range(at: 2))
        let cleaned = formulaBlock.replacingOccurrences(of: "<br>", with: "")
            .replacingOccurrences(of: "<br />", with: "")
        let fullMatch = nsRes.substring(with: match.range(at: 0))
        let replaced = "\(openTag)\(cleaned)</p>"
        newRes = newRes.replacingOccurrences(of: fullMatch, with: replaced)
    }

    return transformGitHubAlerts(in: newRes)
}

// MARK: - GitHub Alerts

private struct GitHubAlertKind {
    let className: String
    let title: String
    let iconPath: String
}

// Octicon 16px paths (info, light-bulb, report, alert, stop), same icons GitHub renders.
private let githubAlertKinds: [String: GitHubAlertKind] = [
    "NOTE": GitHubAlertKind(
        className: "note", title: "Note",
        iconPath: "M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-6.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13Z"
            + "M6.5 7.75A.75.75 0 0 1 7.25 7h1a.75.75 0 0 1 .75.75v2.75h.25a.75.75 0 0 1 0 1.5h-2a.75.75 0 0 1 0-1.5h.25v-2h-.25a.75.75 0 0 1-.75-.75Z"
            + "M8 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"),
    "TIP": GitHubAlertKind(
        className: "tip", title: "Tip",
        iconPath: "M8 1.5c-2.363 0-4 1.69-4 3.75 0 .984.424 1.625.984 2.304l.214.253c.223.264.47.556.673.848.284.411.537.896.621 1.49"
            + "a.75.75 0 0 1-1.484.211c-.04-.282-.163-.547-.37-.847a8.456 8.456 0 0 0-.542-.68c-.084-.1-.173-.205-.268-.32"
            + "C3.201 7.75 2.5 6.766 2.5 5.25 2.5 2.31 4.863 0 8 0s5.5 2.31 5.5 5.25c0 1.516-.701 2.5-1.328 3.259-.095.115-.184.22-.268.319"
            + "-.207.245-.383.453-.541.681-.208.3-.33.565-.37.847a.751.751 0 0 1-1.485-.212c.084-.593.337-1.078.621-1.489"
            + ".203-.292.45-.584.673-.848.075-.088.147-.173.213-.253.561-.679.985-1.32.985-2.304 0-2.06-1.637-3.75-4-3.75Z"
            + "M5.75 12h4.5a.75.75 0 0 1 0 1.5h-4.5a.75.75 0 0 1 0-1.5ZM6 15.25a.75.75 0 0 1 .75-.75h2.5a.75.75 0 0 1 0 1.5h-2.5a.75.75 0 0 1-.75-.75Z"),
    "IMPORTANT": GitHubAlertKind(
        className: "important", title: "Important",
        iconPath: "M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v9.5A1.75 1.75 0 0 1 14.25 13H8.06l-2.573 2.573"
            + "A1.458 1.458 0 0 1 3 14.543V13H1.75A1.75 1.75 0 0 1 0 11.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.5c0 .138.112.25.25.25h2"
            + "a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h6.5a.25.25 0 0 0 .25-.25v-9.5a.25.25 0 0 0-.25-.25Z"
            + "m7 2.25v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 9a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"),
    "WARNING": GitHubAlertKind(
        className: "warning", title: "Warning",
        iconPath: "M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Z"
            + "m1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Z"
            + "m.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"),
    "CAUTION": GitHubAlertKind(
        className: "caution", title: "Caution",
        iconPath: "M4.47.22A.749.749 0 0 1 5 0h6c.199 0 .389.079.53.22l4.25 4.25c.141.14.22.331.22.53v6a.749.749 0 0 1-.22.53"
            + "l-4.25 4.25A.749.749 0 0 1 11 16H5a.749.749 0 0 1-.53-.22L.22 11.53A.749.749 0 0 1 0 11V5c0-.199.079-.389.22-.53Z"
            + "m.84 1.28L1.5 5.31v5.38l3.81 3.81h5.38l3.81-3.81V5.31L10.69 1.5ZM8 4a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5"
            + "A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"),
]

private let githubAlertOpenRegex: NSRegularExpression = {
    let pattern = #"<blockquote([^>]*)>\s*<p([^>]*)>\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        preconditionFailure("githubAlertOpenRegex literal is invalid: \(pattern)")
    }
    return regex
}()

/// Converts GitHub Alert blockquotes (`> [!NOTE]` etc.) in rendered HTML into
/// `<div class="markdown-alert markdown-alert-*">` callouts with a styled title row.
/// Runs on cmark output, so `[!NOTE]` inside code blocks never matches (no `<blockquote><p>` shape).
func transformGitHubAlerts(in html: String) -> String {
    guard html.contains("[!") else { return html }

    let result = NSMutableString(string: html)
    let matches = githubAlertOpenRegex.matches(in: html, options: [], range: NSRange(location: 0, length: result.length))

    // Right-to-left so earlier match ranges stay valid; an outer alert's closing-tag
    // scan happens after its inner blockquotes were already rewritten, which keeps
    // the <blockquote> depth count balanced.
    for match in matches.reversed() {
        let blockquoteAttrs = result.substring(with: match.range(at: 1))
        let paragraphAttrs = result.substring(with: match.range(at: 2))
        let marker = result.substring(with: match.range(at: 3)).uppercased()
        guard let kind = githubAlertKinds[marker] else { continue }

        // The marker must be alone on its line: after `[!X]` cmark emits `<br />`
        // (hardbreaks), a space (nobreaks), a newline, or `</p>` when the quote is marker-only.
        var bodyStart = match.range.location + match.range.length
        var bodyOpensParagraph = true
        if let skipped = skipAlertMarkerTail(in: result, from: bodyStart) {
            bodyStart = skipped.nextIndex
            bodyOpensParagraph = skipped.opensParagraph
        } else {
            continue
        }

        guard let closeRange = matchingBlockquoteClose(in: result, from: bodyStart) else { continue }

        let body = result.substring(with: NSRange(location: bodyStart, length: closeRange.location - bodyStart))
        let icon =
            "<svg class=\"markdown-alert-icon\" viewBox=\"0 0 16 16\" aria-hidden=\"true\"><path d=\"\(kind.iconPath)\"/></svg>"
        var replacement = "<div class=\"markdown-alert markdown-alert-\(kind.className)\"\(blockquoteAttrs)>\n"
        replacement += "<p class=\"markdown-alert-title\">\(icon)\(kind.title)</p>\n"
        if bodyOpensParagraph {
            replacement += "<p\(paragraphAttrs)>"
        }
        replacement += body
        replacement += "</div>"

        let fullRange = NSRange(location: match.range.location, length: closeRange.location + closeRange.length - match.range.location)
        result.replaceCharacters(in: fullRange, with: replacement)
    }

    return result as String
}

/// Skips the separator right after an alert marker. Returns nil when the marker is
/// glued to other text (`[!NOTE]:`), which GitHub does not treat as an alert.
private func skipAlertMarkerTail(in html: NSMutableString, from index: Int) -> (nextIndex: Int, opensParagraph: Bool)? {
    var cursor = index
    if hasPrefix("</p>", in: html, at: cursor) {
        cursor += 4
        while cursor < html.length, isASCIIWhitespace(html.character(at: cursor)) {
            cursor += 1
        }
        return (cursor, false)
    }
    if hasPrefix("<br />", in: html, at: cursor) {
        cursor += 6
    } else if hasPrefix("<br>", in: html, at: cursor) {
        cursor += 4
    } else if cursor < html.length, isASCIIWhitespace(html.character(at: cursor)) {
        cursor += 1
    } else {
        return nil
    }
    while cursor < html.length, isASCIIWhitespace(html.character(at: cursor)) {
        cursor += 1
    }
    return (cursor, true)
}

private func hasPrefix(_ prefix: String, in html: NSMutableString, at index: Int) -> Bool {
    let length = (prefix as NSString).length
    guard index + length <= html.length else { return false }
    return html.substring(with: NSRange(location: index, length: length)) == prefix
}

private func isASCIIWhitespace(_ char: unichar) -> Bool {
    return char == 0x20 || char == 0x0A || char == 0x09 || char == 0x0D
}

private func matchingBlockquoteClose(in html: NSMutableString, from index: Int) -> NSRange? {
    var depth = 1
    var cursor = index
    let closeTag = "</blockquote>"
    while cursor < html.length {
        let searchRange = NSRange(location: cursor, length: html.length - cursor)
        let close = html.range(of: closeTag, options: [], range: searchRange)
        guard close.location != NSNotFound else { return nil }
        // Only opens before this close can affect depth; bounding the search
        // avoids rescanning the whole document tail per iteration.
        let openSearchRange = NSRange(location: cursor, length: close.location - cursor)
        let open = html.range(of: "<blockquote", options: [], range: openSearchRange)
        if open.location != NSNotFound, open.location < close.location {
            depth += 1
            cursor = open.location + open.length
        } else {
            depth -= 1
            if depth == 0 { return close }
            cursor = close.location + close.length
        }
    }
    return nil
}
