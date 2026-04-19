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

    return newRes
}
