import CMarkGFM
import Foundation

extension String {
    func matches(_ pattern: String) -> Bool {
        return self.range(of: pattern, options: .regularExpression) != nil
    }
}

@MainActor func renderMarkdownHTML(markdown: String) -> String? {
    cmark_gfm_core_extensions_ensure_registered()

    guard let parser = cmark_parser_new(CMARK_OPT_FOOTNOTES) else { return nil }
    defer { cmark_parser_free(parser) }

    // 附加常见的 GFM 扩展
    let extensions = ["table", "emoji", "footnotes", "strikethrough", "tasklist"]
    for extName in extensions {
        if let ext = cmark_find_syntax_extension(extName) {
            cmark_parser_attach_syntax_extension(parser, ext)
        }
    }

    cmark_parser_feed(parser, markdown, markdown.utf8.count)
    guard let node = cmark_parser_finish(parser) else { return nil }

    var res: String
    if UserDefaultsManagement.editorLineBreak == "Github" {
        res = String(cString: cmark_render_html(node, CMARK_OPT_UNSAFE | CMARK_OPT_NOBREAKS, nil))
    } else {
        res = String(cString: cmark_render_html(node, CMARK_OPT_UNSAFE | CMARK_OPT_HARDBREAKS, nil))
    }

    // 后处理：去除公式块内的 <br> 和 <br />
    let pattern = #"<p>(\$\$[\s\S]*?\$\$)<\/p>"#
    let regex = try? NSRegularExpression(pattern: pattern, options: [])
    let nsRes = res as NSString
    var newRes = res
    regex?.enumerateMatches(in: res, options: [], range: NSRange(location: 0, length: nsRes.length)) { match, _, _ in
        guard let match = match else { return }
        let formulaBlock = nsRes.substring(with: match.range(at: 1))
        let cleaned = formulaBlock.replacingOccurrences(of: "<br>", with: "")
            .replacingOccurrences(of: "<br />", with: "")
        let fullMatch = nsRes.substring(with: match.range(at: 0))
        let replaced = "<p>\(cleaned)</p>"
        newRes = newRes.replacingOccurrences(of: fullMatch, with: replaced)
    }

    return newRes
}
