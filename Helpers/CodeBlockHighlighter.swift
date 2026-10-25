import Cocoa
import Highlightr

@MainActor
enum CodeBlockHighlighter {
    private static var cachedCodeBlockRegex: NSRegularExpression?

    static func getCodeBlockRegex(pattern: String) -> NSRegularExpression? {
        if let cached = cachedCodeBlockRegex {
            return cached
        }

        guard
            let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.allowCommentsAndWhitespace, .anchorsMatchLines]
            )
        else {
            return nil
        }

        cachedCodeBlockRegex = regex
        return regex
    }

    static func highlightCode(
        attributedString: NSMutableAttributedString,
        range: NSRange,
        language: String? = nil
    ) {
        guard range.upperBound <= attributedString.length else {
            return
        }

        if NotesTextProcessor.shouldSkipCodeHighlighting {
            applyBasicCodeStyle(attributedString: attributedString, range: range)
            return
        }

        let maxCodeBlockSize = NotesTextProcessor.shouldUseSimplifiedHighlighting ? 500 : 3000
        if range.length > maxCodeBlockSize {
            applyBasicCodeStyle(attributedString: attributedString, range: range)
            return
        }

        guard let highlighter = NotesTextProcessor.getHighlighter() else {
            applyBasicCodeStyle(attributedString: attributedString, range: range)
            return
        }

        let codeString = attributedString.mutableString.substring(with: range)
        let preDefinedLanguage = language ?? NotesTextProcessor.getLanguage(codeString)

        guard let code = highlighter.highlight(codeString, as: preDefinedLanguage),
            code.string == attributedString.mutableString.substring(with: range)
        else {
            applyBasicCodeStyle(attributedString: attributedString, range: range)
            return
        }

        code.enumerateAttributes(in: NSRange(location: 0, length: code.length)) { attrs, locRange, _ in
            let fixedRange = NSRange(
                location: range.location + locRange.location,
                length: min(locRange.length, attributedString.length - (range.location + locRange.location))
            )

            guard fixedRange.length > 0, fixedRange.upperBound <= attributedString.length else {
                return
            }

            attributedString.addAttributes(attrs, range: fixedRange)
            if let colour = attrs[.foregroundColor] as? NSColor {
                attributedString.addAttribute(.foregroundColor, value: editorColor(forThemeColour: colour), range: fixedRange)
            }
            if let font = NotesTextProcessor.codeFont {
                attributedString.addAttribute(.font, value: font, range: fixedRange)
            }
        }

        attributedString.addAttribute(.codeBlock, value: true, range: range)
        if let language = preDefinedLanguage {
            attributedString.addAttribute(.codeLanguage, value: language, range: range)
        } else {
            attributedString.removeAttribute(.codeLanguage, range: range)
        }

        attributedString.fixAttributes(in: range)
    }

    /// Sets every HTML tag in the editor's own text face and size, in the
    /// code colour, leaving text between tags as prose (face picked
    /// 2026-10-19, colour 2026-10-25). Tags in a smaller system face
    /// read as code beside the prose. Never `highlightCode`: that gave an
    /// `<img>` line the code font and the code-block mark, and the mark then
    /// made the next keystroke re-highlight the whole paragraph as code.
    static func highlightInlineHTML(attributedString: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0, range.upperBound <= attributedString.length else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NotesTextProcessor.font,
            .foregroundColor: NotesTextProcessor.codeColor,
        ]
        let source = attributedString.string
        htmlTagRegex.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let tag = match?.range, tag.upperBound <= attributedString.length,
                NotesTextProcessor.getSpanCodeBlockRange(content: attributedString, range: tag) == nil
            else { return }
            attributedString.fixAttributes(in: tag)
            attributedString.addAttributes(attributes, range: tag)
        }
    }

    /// Every tag on its own, opening, closing, self-closing or a comment, so
    /// nested and multi-line HTML (`<video><source></video>`, a `<table>`)
    /// reads the same as a lone `<img>`. An autolink (`<https://…>`) is not a
    /// tag: its name would run into a colon.
    private static let htmlTagRegex = try! NSRegularExpression(
        pattern: "<!--.*?-->|</?[A-Za-z][A-Za-z0-9-]*(?:\\s[^<>]*)?/?>")

    static func highlightFencedAndIndentCodeBlocks(attributedString: NSMutableAttributedString, pattern: String) {
        let range = NSRange(0..<attributedString.length)
        guard range.length > 0 else { return }

        guard let regex = getCodeBlockRegex(pattern: pattern) else {
            return
        }

        regex.enumerateMatches(in: attributedString.string, range: range) { result, _, _ in
            guard let codeRange = result?.range,
                codeRange.upperBound <= attributedString.length
            else {
                return
            }
            highlightCode(attributedString: attributedString, range: codeRange)
        }
    }

    /// Highlightr draws with atom-one-light or tomorrow-night-blue, whose
    /// plain text is a grey and whose comments turn blue in dark. Each role is
    /// moved onto the editor's code colours: comments to the markup grey,
    /// keywords, types, numbers and titles to purple, the rest (plain text,
    /// strings) to the code gold.
    static func editorColor(forThemeColour colour: NSColor) -> NSColor {
        guard let srgb = colour.usingColorSpace(.sRGB) else { return NotesTextProcessor.codeColor }
        let hex =
            Int(round(srgb.redComponent * 255)) << 16 | Int(round(srgb.greenComponent * 255)) << 8
            | Int(round(srgb.blueComponent * 255))
        switch hex {
        case 0xA0A1A7, 0x7285B7:
            return NotesTextProcessor.syntaxColor
        case 0xA626A4, 0x986801, 0x0184BB, 0x4078F2, 0xC18401, 0xE45649,
            0xEBBBFF, 0xFFC58F, 0xFFEEAD, 0xBBDAFF, 0xFF9DA4:
            return Theme.editorCodeKeywordColor
        default:
            return NotesTextProcessor.codeColor
        }
    }

    private static func applyBasicCodeStyle(attributedString: NSMutableAttributedString, range: NSRange) {
        guard range.upperBound <= attributedString.length,
            let codeFont = NotesTextProcessor.codeFont
        else {
            return
        }

        attributedString.addAttribute(.font, value: codeFont, range: range)
        attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.codeColor, range: range)
        attributedString.addAttribute(.codeBlock, value: true, range: range)
        attributedString.removeAttribute(.codeLanguage, range: range)
        attributedString.fixAttributes(in: range)
    }
}
