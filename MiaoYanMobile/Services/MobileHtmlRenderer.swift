import Foundation
import CMarkGFM

enum MobileHtmlRenderer {
    static func render(markdown: String, fontSize: Int = 17) -> String {
        let body = markdownToHTML(markdown)
        let css = loadCSS()
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5, user-scalable=yes">
        <style>
        :root { --font-size: \(fontSize)px; }
        \(css)
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func markdownToHTML(_ markdown: String) -> String {
        cmark_gfm_core_extensions_ensure_registered()
        guard let parser = cmark_parser_new(CMARK_OPT_FOOTNOTES) else { return "" }
        defer { cmark_parser_free(parser) }

        for extName in ["table", "footnotes", "strikethrough", "tasklist"] {
            if let ext = cmark_find_syntax_extension(extName) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        cmark_parser_feed(parser, markdown, markdown.utf8.count)
        guard let node = cmark_parser_finish(parser) else { return "" }
        return String(cString: cmark_render_html(node, CMARK_OPT_UNSAFE | CMARK_OPT_HARDBREAKS, nil))
    }

    private static func loadCSS() -> String {
        guard let url = Bundle.main.url(forResource: "mobile-reader", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else {
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
    }
    @media (prefers-color-scheme: dark) {
        body { background: #1c1c1e; color: #e5e5ea; }
    }
    """
}
