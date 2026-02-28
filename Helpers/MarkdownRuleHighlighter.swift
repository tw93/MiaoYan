import Cocoa

@MainActor
enum MarkdownRuleHighlighter {
    static func highlightBasicMarkdown(attributedString: NSMutableAttributedString, range: NSRange? = nil, note: Note) {
        let range = range ?? NSRange(0..<attributedString.length)
        let string = attributedString.string

        guard range.upperBound <= attributedString.length else { return }

        attributedString.removeAttribute(.codeBlock, range: range)
        attributedString.removeAttribute(.codeLanguage, range: range)
        attributedString.addAttribute(.font, value: NotesTextProcessor.font, range: range)
        attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.fontColor, range: range)

        NotesTextProcessor.headersAtxRegex.matches(string, range: range) { result in
            guard let range = result?.range, range.upperBound <= attributedString.length else { return }
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.titleColor, range: range)
        }

        NotesTextProcessor.listRegex.matches(string, range: range) { result in
            guard let range = result?.range, range.upperBound <= attributedString.length else { return }
            NotesTextProcessor.listOpeningRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range, innerRange.upperBound <= attributedString.length else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.listColor, range: innerRange)
            }
        }

        NotesTextProcessor.blockQuoteRegex.matches(string, range: range) { result in
            guard let range = result?.range, range.upperBound <= attributedString.length else { return }
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.listColor, range: range)
        }

        if let regex = NotesTextProcessor.getCodeBlockRegex() {
            regex.enumerateMatches(in: string, options: [], range: range) { result, _, _ in
                guard let codeRange = result?.range, codeRange.upperBound <= attributedString.length else { return }

                let codeColor =
                    UserDataService.instance.isDark
                    ? NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
                    : NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)

                if let codeFont = NotesTextProcessor.codeFont {
                    attributedString.addAttribute(.font, value: codeFont, range: codeRange)
                }
                attributedString.addAttribute(.foregroundColor, value: codeColor, range: codeRange)
                attributedString.addAttribute(.codeBlock, value: true, range: codeRange)
                attributedString.removeAttribute(.codeLanguage, range: codeRange)
            }
        }

        NotesTextProcessor.imageRegex.matches(string, range: range) { result in
            guard let range = result?.range, range.upperBound <= attributedString.length else { return }
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.linkColor, range: range)
        }

        attributedString.fixAttributes(in: range)
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func highlightMarkdown(attributedString: NSMutableAttributedString, paragraphRange: NSRange? = nil, note: Note) {
        let paragraphRange = paragraphRange ?? NSRange(0..<attributedString.length)
        let isFullScan = attributedString.length == paragraphRange.upperBound && paragraphRange.lowerBound == 0
        let string = attributedString.string

        let quoteFont = NotesTextProcessor.quoteFont(CGFloat(UserDefaultsManagement.fontSize))
        let hiddenFont = NSFont.systemFont(ofSize: 0.1)
        let hiddenColor = NSColor.clear
        let hiddenAttributes: [NSAttributedString.Key: Any] = [
            .font: hiddenFont,
            .foregroundColor: hiddenColor,
        ]

        func hideSyntaxIfNecessary(range: @autoclosure () -> NSRange) {
            guard NotesTextProcessor.hideSyntax else { return }
            attributedString.addAttributes(hiddenAttributes, range: range())
        }

        attributedString.enumerateAttribute(.link, in: paragraphRange) { value, range, _ in
            guard value != nil,
                range.upperBound <= attributedString.length,
                attributedString.attribute(.attachment, at: range.location, effectiveRange: nil) == nil
            else {
                return
            }
            attributedString.removeAttribute(.link, range: range)
        }

        attributedString.enumerateAttribute(.strikethroughStyle, in: paragraphRange) { value, range, _ in
            guard value != nil, range.upperBound <= attributedString.length else {
                return
            }
            attributedString.removeAttribute(.strikethroughStyle, range: range)
        }

        attributedString.addAttribute(.font, value: NotesTextProcessor.font, range: paragraphRange)
        attributedString.fixAttributes(in: paragraphRange)

        attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.fontColor, range: paragraphRange)
        attributedString.enumerateAttribute(.foregroundColor, in: paragraphRange) { value, range, _ in
            guard value is NSColor,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.fontColor, range: range)
        }

        NotesTextProcessor.italicRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.fixAttributes(in: range)
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.titleColor, range: range)
        }

        NotesTextProcessor.boldRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.fixAttributes(in: range)
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.htmlColor, range: range)
        }

        NotesTextProcessor.strikeRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.fixAttributes(in: range)
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.htmlColor, range: range)
        }

        NotesTextProcessor.codeLineRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.fixAttributes(in: range)
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.htmlColor, range: range)
        }

        NotesTextProcessor.headersSetextRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.fixAttributes(in: range)

            NotesTextProcessor.headersSetextUnderlineRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range,
                    innerRange.upperBound <= attributedString.length
                else {
                    return
                }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                hideSyntaxIfNecessary(range: NSRange(location: innerRange.location, length: innerRange.length))
            }
        }

        NotesTextProcessor.headersAtxRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.titleColor, range: range)
            attributedString.fixAttributes(in: range)

            NotesTextProcessor.headersAtxOpeningRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range,
                    innerRange.upperBound <= attributedString.length
                else {
                    return
                }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.titleColor, range: innerRange)
                let syntaxRange = NSRange(location: innerRange.location, length: innerRange.length + 1)
                guard syntaxRange.upperBound <= attributedString.length else { return }
                hideSyntaxIfNecessary(range: syntaxRange)
            }

            NotesTextProcessor.headersAtxClosingRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range,
                    innerRange.upperBound <= attributedString.length
                else {
                    return
                }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.titleColor, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }
        }

        NotesTextProcessor.referenceLinkRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: range)
        }

        NotesTextProcessor.listRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                range.upperBound <= attributedString.length
            else {
                return
            }

            NotesTextProcessor.listOpeningRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range,
                    innerRange.upperBound <= attributedString.length
                else {
                    return
                }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.listColor, range: innerRange)
            }
        }

        NotesTextProcessor.anchorRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            attributedString.fixAttributes(in: range)
            NotesTextProcessor.openingSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
            NotesTextProcessor.closingSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
            NotesTextProcessor.parenRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                let initialSyntaxRange = NSRange(location: innerRange.location, length: 1)
                let finalSyntaxRange = NSRange(location: innerRange.location + innerRange.length - 1, length: 1)
                hideSyntaxIfNecessary(range: initialSyntaxRange)
                hideSyntaxIfNecessary(range: finalSyntaxRange)
            }
        }

        NotesTextProcessor.anchorInlineRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            attributedString.fixAttributes(in: range)

            var destinationLink: String?

            NotesTextProcessor.coupleRoundRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)

                guard let linkRange = result?.range(at: 3), linkRange.length > 0 else { return }

                var substring = attributedString.mutableString.substring(with: linkRange)

                guard !substring.isEmpty else { return }
                guard let note = EditTextView.note else { return }

                if substring.starts(with: "/i/") || substring.starts(with: "/files/"), let path = note.project.url.appendingPathComponent(substring).path.removingPercentEncoding {
                    substring = "file://" + path
                }

                destinationLink = substring
                attributedString.addAttribute(.link, value: substring, range: linkRange)
                hideSyntaxIfNecessary(range: innerRange)
            }

            NotesTextProcessor.openingSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }

            NotesTextProcessor.closingSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }

            guard destinationLink != nil else { return }

            NotesTextProcessor.coupleSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                var _range = innerRange
                _range.location += 1
                _range.length -= 2

                let substring = attributedString.mutableString.substring(with: _range)
                guard substring.lengthOfBytes(using: .utf8) > 0 else { return }

                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.linkColor, range: _range)
            }
        }

        NotesTextProcessor.imageRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            attributedString.fixAttributes(in: range)

            if NotesTextProcessor.hideSyntax {
                attributedString.addAttribute(.font, value: hiddenFont, range: range)
            }
            NotesTextProcessor.imageOpeningSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.linkColor, range: innerRange)
            }
            NotesTextProcessor.imageClosingSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
        }

        NotesTextProcessor.appUrlRegex.matches(string, range: paragraphRange) { result in
            guard let innerRange = result?.range else { return }
            var _range = innerRange
            _range.location += 2
            _range.length -= 4

            let appLink = attributedString.mutableString.substring(with: _range)

            attributedString.addAttribute(.link, value: "miaoyan://goto/" + appLink, range: _range)
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.linkColor, range: _range)
            if let range = result?.range(at: 0) {
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: range)
            }

            if let range = result?.range(at: 2) {
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: range)
            }
        }

        NotesTextProcessor.blockQuoteRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            attributedString.addAttribute(.font, value: quoteFont, range: range)
            attributedString.fixAttributes(in: range)
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.listColor, range: range)
            NotesTextProcessor.blockQuoteOpeningRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.listColor, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }
        }

        NotesTextProcessor.imageInlineRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }

            if let linkRange = result?.range(at: 3) {
                let link = attributedString.mutableString.substring(with: linkRange).removingPercentEncoding

                if let link = link, let url = note.getImageUrl(imageName: link) {
                    attributedString.addAttribute(.link, value: url, range: linkRange)
                    attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.linkColor, range: linkRange)
                }
            }

            NotesTextProcessor.imageOpeningSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
            NotesTextProcessor.imageClosingSquareRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
            NotesTextProcessor.parenRegex.matches(string, range: range) { innerResult in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
        }

        NotesTextProcessor.htmlRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            attributedString.fixAttributes(in: range)
            NotesTextProcessor.highlightCode(attributedString: attributedString, range: range, language: "html")
        }

        NotesTextProcessor.imageHtmlRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range else { return }
            attributedString.fixAttributes(in: range)
            NotesTextProcessor.highlightCode(attributedString: attributedString, range: range, language: "html")
        }

        NotesTextProcessor.emojiRegex.matches(string, range: paragraphRange) { result in
            guard let range = result?.range,
                NotesTextProcessor.getSpanCodeBlockRange(content: attributedString, range: range) == nil,
                NotesTextProcessor.getFencedCodeBlockRange(paragraphRange: range, string: attributedString) == nil
            else { return }

            let substring = attributedString.mutableString.substring(with: range)
            if !substring.isNumber {
                attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: CGFloat(UserDefaultsManagement.fontSize - 2)), range: range)
                attributedString.fixAttributes(in: range)
            }
        }

        if UserDefaultsManagement.fontName == "SF Mono" {
            NotesTextProcessor.blankRegex.matches(string, range: paragraphRange) { result in
                guard let range = result?.range else { return }
                attributedString.addAttribute(.font, value: NotesTextProcessor.publicFont!, range: range)
            }
        }

        if UserDefaultsManagement.fontName == "Times New Roman", NotesTextProcessor.georgiaFont != nil {
            NotesTextProcessor.englishAndSymbolRegex.matches(string, range: paragraphRange) { result in
                guard let range = result?.range else { return }
                attributedString.addAttribute(.font, value: NotesTextProcessor.georgiaFont!, range: range)
            }
        }

        if NotesTextProcessor.monacoFont != nil {
            NotesTextProcessor.allTodoInlineRegex.matches(string, range: paragraphRange) { result in
                guard let range = result?.range else { return }
                let middleRange = NSRange(location: range.location + 3, length: 1)

                attributedString.addAttribute(.font, value: NotesTextProcessor.monacoFont!, range: middleRange)
            }
        }

        attributedString.enumerateAttribute(.attachment, in: paragraphRange) { value, range, _ in
            guard value != nil,
                range.upperBound <= attributedString.length,
                let todo = attributedString.attribute(.todo, at: range.location, effectiveRange: nil)
            else {
                return
            }
            let strikeRange = attributedString.mutableString.paragraphRange(for: range)
            guard strikeRange.upperBound <= attributedString.length else { return }
            attributedString.addAttribute(.strikethroughStyle, value: todo, range: strikeRange)
        }

        if isFullScan {
            NotesTextProcessor.checkBackTick(styleApplier: attributedString)
        }
    }
}
