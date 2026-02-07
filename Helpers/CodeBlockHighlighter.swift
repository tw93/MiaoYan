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

    private static func applyBasicCodeStyle(attributedString: NSMutableAttributedString, range: NSRange) {
        guard range.upperBound <= attributedString.length,
            let codeFont = NotesTextProcessor.codeFont
        else {
            return
        }

        let codeColor =
            UserDataService.instance.isDark
            ? NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
            : NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)

        attributedString.addAttribute(.font, value: codeFont, range: range)
        attributedString.addAttribute(.foregroundColor, value: codeColor, range: range)
        attributedString.addAttribute(.codeBlock, value: true, range: range)
        attributedString.removeAttribute(.codeLanguage, range: range)
        attributedString.fixAttributes(in: range)
    }
}
