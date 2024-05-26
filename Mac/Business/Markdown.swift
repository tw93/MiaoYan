import libcmark_gfm

func renderMarkdownHTML(markdown: String) -> String? {
    cmark_gfm_core_extensions_ensure_registered()

    guard let parser = cmark_parser_new(CMARK_OPT_FOOTNOTES) else { return nil }
    defer { cmark_parser_free(parser) }

    // 附加常见的 GFM 扩展
    let extensions = ["table", "autolink", "emoji", "footnotes", "strikethrough", "tasklist"]
    for extName in extensions {
        if let ext = cmark_find_syntax_extension(extName) {
            cmark_parser_attach_syntax_extension(parser, ext)
        }
    }

    cmark_parser_feed(parser, markdown, markdown.utf8.count)
    guard let node = cmark_parser_finish(parser) else { return nil }

    var res = String(cString: cmark_render_html(node, CMARK_OPT_UNSAFE | CMARK_OPT_HARDBREAKS, nil))
    if UserDefaultsManagement.editorLineBreak == "Github" {
        res = String(cString: cmark_render_html(node, CMARK_OPT_UNSAFE | CMARK_OPT_NOBREAKS, nil))
    }

    return res
}
