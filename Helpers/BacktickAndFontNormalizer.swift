import Cocoa

@MainActor
enum BacktickAndFontNormalizer {
    static func normalize(styleApplier: NSMutableAttributedString, paragraphRange: NSRange? = nil) {
        let range = paragraphRange ?? NSRange(0..<styleApplier.length)
        guard range.upperBound <= styleApplier.length else { return }

        styleApplier.enumerateAttribute(.backgroundColor, in: range) { value, innerRange, _ in
            guard value != nil,
                innerRange.upperBound <= styleApplier.length,
                let font = UserDefaultsManagement.noteFont
            else {
                return
            }
            styleApplier.removeAttribute(.backgroundColor, range: innerRange)
            styleApplier.addAttribute(.font, value: font, range: innerRange)
            styleApplier.fixAttributes(in: innerRange)
        }

        NotesTextProcessor.codeSpanRegex.matches(styleApplier.string, range: range) { result in
            guard let matchRange = result?.range,
                matchRange.upperBound <= styleApplier.length
            else {
                return
            }
            styleApplier.addAttribute(.foregroundColor, value: NotesTextProcessor.htmlColor, range: matchRange)
        }

        if UserDefaultsManagement.fontName == "Times New Roman" {
            NotesTextProcessor.englishAndSymbolRegex.matches(styleApplier.string, range: range) { result in
                guard let matchRange = result?.range,
                    matchRange.upperBound <= styleApplier.length
                else {
                    return
                }
                if let georgiaFont = NotesTextProcessor.georgiaFont {
                    styleApplier.addAttribute(.font, value: georgiaFont, range: matchRange)
                }
            }

            if let monacoFont = NotesTextProcessor.monacoFont {
                NotesTextProcessor.allTodoInlineRegex.matches(styleApplier.string, range: range) { result in
                    guard let matchRange = result?.range,
                        matchRange.upperBound <= styleApplier.length
                    else {
                        return
                    }
                    let middleRange = NSRange(location: matchRange.location + 3, length: 1)
                    guard middleRange.upperBound <= styleApplier.length else { return }
                    styleApplier.addAttribute(.font, value: monacoFont, range: middleRange)
                }
            }
        }
    }
}
