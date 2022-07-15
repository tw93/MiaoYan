import Foundation

#if os(OSX)
    import Carbon.HIToolbox
    import Cocoa
    typealias Font = NSFont
    typealias TextView = EditTextView
    typealias Color = NSColor
#else
    import UIKit
    typealias Font = UIFont
    typealias TextView = EditTextView
    typealias Color = UIColor
#endif

public class TextFormatter {
    private var attributedString: NSMutableAttributedString
    private var attributedSelected: NSAttributedString
    private var type: NoteType
    private var textView: TextView
    private var note: Note
    private var storage: NSTextStorage
    private var selectedRange: NSRange
    private var range: NSRange
    private var newSelectedRange: NSRange?
    private var cursor: Int?

    private var prevSelectedString: NSAttributedString
    private var prevSelectedRange: NSRange

    private var shouldScanMarkdown: Bool

    init(textView: TextView, note: Note, shouldScanMarkdown: Bool = true) {
        range = textView.selectedRange

        #if os(OSX)
            storage = textView.textStorage!
            attributedSelected = textView.attributedString()
            if textView.typingAttributes[.font] == nil {
                textView.typingAttributes[.font] = UserDefaultsManagement.noteFont
            }
        #else
            storage = textView.textStorage
            attributedSelected = textView.attributedText
        #endif

        attributedString = NSMutableAttributedString(attributedString: attributedSelected.attributedSubstring(from: range))
        selectedRange = NSRange(0..<attributedString.length)

        type = note.type
        self.textView = textView
        self.note = note

        prevSelectedRange = range
        prevSelectedString = storage.attributedSubstring(from: prevSelectedRange)

        self.shouldScanMarkdown = note.isMarkdown() ? shouldScanMarkdown : false
    }

    func getString() -> NSMutableAttributedString {
        attributedString
    }

    func bold() {
        if note.isMarkdown() {
            let string = "**" + attributedString.string + "**"
            let location = string.count == 4 ? range.location + 2 : range.upperBound + 4
            insertText(string, selectRange: NSMakeRange(location, 0))
        }
    }

    func italic() {
        if note.isMarkdown() {
            let string = "*" + attributedString.string + "*"
            let location = string.count == 2 ? range.location + 1 : range.upperBound + 2
            insertText(string, selectRange: NSMakeRange(location, 0))
        }
    }

    public func underline() {
        if note.isMarkdown() {
            let string = "<u>" + attributedString.string + "</u>"
            let location = string.count == 7 ? range.location + 3 : range.upperBound + 7

            replaceWith(string: string)
            setSelectedRange(NSMakeRange(location, 0))
        }
    }

    public func deleteline() {
        if note.isMarkdown() {
            let string = "~~" + attributedString.string + "~~"
            let location = string.count == 4 ? range.location + 2 : range.upperBound + 4

            replaceWith(string: string)
            setSelectedRange(NSMakeRange(location, 0))
        }
    }

    public func tab() {
        guard let pRange = getParagraphRange() else { return }
        let padding = "    "

        guard range.length > 0 else {
            let text = storage.attributedSubstring(from: pRange).string
            #if os(OSX)
                let location = textView.selectedRange().location
                textView.insertText(padding + text, replacementRange: pRange)
                setSelectedRange(NSMakeRange(location + padding.count, 0))
            #else
                replaceWith(string: padding + text, range: pRange)
                setSelectedRange(NSMakeRange(range.upperBound + padding.count, 0))
            #endif
            return
        }

        let string = storage.attributedSubstring(from: pRange).string
        var lines = [String]()
        string.enumerateLines { line, _ in
            lines.append(padding + line)
        }

        var result = lines.joined(separator: "\n")
        if pRange.upperBound != storage.length {
            result = result + "\n"
        }

        #if os(OSX)
            if textView.textStorage?.length == 0 {
                EditTextView.shouldForceRescan = true
            }

            textView.insertText(result, replacementRange: pRange)
        #else
            replaceWith(string: result)
        #endif

        setSelectedRange(NSRange(location: pRange.lowerBound, length: result.count))
    }

    func unTab() {
        guard let pRange = getParagraphRange() else { return }
        guard range.length > 0 else {
            var diff = 0
            var text = storage.attributedSubstring(from: pRange).string
            if text.starts(with: "    ") {
                diff = 4
                text = String(text.dropFirst(4))
            } else if text.starts(with: "\t") {
                diff = 1
                text = String(text.dropFirst())
            } else {
                return
            }

            guard text.count >= 0 else { return }

            #if os(OSX)
                textView.insertText(text, replacementRange: pRange)
            #else
                insertText(text, replacementRange: pRange)
            #endif

            setSelectedRange(NSRange(location: range.location - diff, length: 0))
            return
        }

        let string = storage.attributedSubstring(from: pRange).string
        var resultList: [String] = []
        string.enumerateLines { line, _ in
            var line = line
            if !line.isEmpty {
                if line.first == "\t" {
                    line = String(line.dropFirst())
                } else if line.starts(with: "    ") {
                    line = String(line.dropFirst(4))
                }
            }

            resultList.append(line)
        }

        var result = resultList.joined(separator: "\n")
        if pRange.upperBound != storage.length {
            result = result + "\n"
        }

        #if os(OSX)
            textView.insertText(result, replacementRange: pRange)
        #else
            replaceWith(string: result)
        #endif

        let finalRange = NSRange(location: pRange.lowerBound, length: result.count)
        setSelectedRange(finalRange)
    }

    public func header(_ string: String) {
        guard let pRange = getParagraphRange() else { return }

        var prefix = String()
        let selected = textView.selectedRange
        let paragraph = storage.mutableString.substring(with: pRange)

        #if os(OSX)
            prefix = string + " "
        #else
            if paragraph.starts(with: "#") {
                prefix = string
            } else {
                prefix = string + " "
            }
        #endif

        let selectRange = NSRange(location: selected.location + selected.length + prefix.count, length: 0)
        insertText(prefix + paragraph, replacementRange: pRange, selectRange: selectRange)
    }

    public func link() {
        let text = "[" + attributedString.string + "]()"
        replaceWith(string: text, range: range)

        if attributedString.length == 4 {
            setSelectedRange(NSMakeRange(range.location + 1, 0))
        } else {
            setSelectedRange(NSMakeRange(range.upperBound + 3, 0))
        }
    }

    public func image() {
        let text = "![" + attributedString.string + "]()"
        replaceWith(string: text)

        if attributedString.length == 5 {
            setSelectedRange(NSMakeRange(range.location + 2, 0))
        } else {
            setSelectedRange(NSMakeRange(range.upperBound + 4, 0))
        }
    }

    public func tabKey() {
        guard let currentPR = getParagraphRange() else { return }
        let paragraph = storage.attributedSubstring(from: currentPR).string
        let sRange = textView.selectedRange

        // Middle
        if sRange.location != 0 || sRange.location != storage.length,
           paragraph.count == 1,
           note.isMarkdown()
        {
            insertText("\t", replacementRange: sRange)
            return
        }

        // First & Last
        if sRange.location == 0 || sRange.location == storage.length, paragraph.count == 0, note.isMarkdown() {
            #if os(OSX)
                if textView.textStorage?.length == 0 {
                    EditTextView.shouldForceRescan = true
                }
            #else
                if textView.textStorage.length == 0 {
                    EditTextView.shouldForceRescan = true
                }
            #endif

            insertText("\t\n", replacementRange: sRange)
            setSelectedRange(NSRange(location: sRange.location + 1, length: 0))
            return
        }

        insertText("\t")
    }

    public static func getAutocompleteCharsMatch(string: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern:
            "^(( |\t)*\\- \\[[x| ]*\\] )|^(( |\t)*[-|–|—|*|•|>|\\+]{1} )"), let result = regex.firstMatch(in: string, range: NSRange(0..<string.count)) else { return nil }

        return result
    }

    public static func getAutocompleteDigitsMatch(string: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: "^(( |\t)*[0-9]+\\. )"), let result = regex.firstMatch(in: string, range: NSRange(0..<string.count)) else { return nil }

        return result
    }

    private func matchChars(string: NSAttributedString, match: NSTextCheckingResult, prefix: String? = nil) {
        guard string.length >= match.range.upperBound else { return }

        let found = string.attributedSubstring(from: match.range).string
        var newLine = 1

        if textView.selectedRange.upperBound == storage.length {
            newLine = 0
        }

        if found.count + newLine == string.length {
            let range = storage.mutableString.paragraphRange(for: textView.selectedRange)
            let selectRange = NSRange(location: range.location, length: 0)
            insertText("\n", replacementRange: range, selectRange: selectRange)
            return
        }

        insertText("\n" + found)
    }

    private func matchDigits(string: NSAttributedString, match: NSTextCheckingResult) {
        guard string.length >= match.range.upperBound else { return }

        let found = string.attributedSubstring(from: match.range).string

        var newLine = 1

        if textView.selectedRange.upperBound == storage.length {
            newLine = 0
        }

        if found.count + newLine == string.length {
            let range = storage.mutableString.paragraphRange(for: textView.selectedRange)
            let selectRange = NSRange(location: range.location, length: 0)
            insertText("\n", replacementRange: range, selectRange: selectRange)
            return
        }

        if let position = Int(found.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)) {
            let newDigit = found.replacingOccurrences(of: String(position), with: String(position + 1))
            insertText("\n" + newDigit)
        }
    }

    public func newLine() {
        guard let currentParagraphRange = getParagraphRange() else { return }

        let currentParagraph = storage.attributedSubstring(from: currentParagraphRange)
        let selectedRange = textView.selectedRange

        // Autocomplete todo lists

        if selectedRange.location != currentParagraphRange.location, currentParagraphRange.upperBound - 2 < selectedRange.location, currentParagraph.length >= 2 {
            if textView.selectedRange.upperBound > 2 {
                let char = storage.attributedSubstring(from: NSRange(location: textView.selectedRange.upperBound - 2, length: 1))

                if let _ = char.attribute(.todo, at: 0, effectiveRange: nil) {
                    let selectRange = NSRange(location: currentParagraphRange.location, length: 0)
                    insertText("\n", replacementRange: currentParagraphRange, selectRange: selectRange)
                    return
                }
            }

            var todoLocation = -1
            currentParagraph.enumerateAttribute(.todo, in: NSRange(0..<currentParagraph.length), options: []) { value, range, stop in
                guard value != nil else { return }

                todoLocation = range.location
                stop.pointee = true
            }

            if todoLocation > -1 {
                var prefix = String()

                if todoLocation > 0 {
                    prefix = currentParagraph.attributedSubstring(from: NSRange(0..<todoLocation)).string
                }

                #if os(OSX)
                    let string = NSMutableAttributedString(string: "\n" + prefix)

                    insertText(string)
                #else
                    let selectedRange = textView.selectedRange
                    let selectedTextRange = textView.selectedTextRange!
                    let checkbox = NSMutableAttributedString(string: "\n" + prefix)

                    textView.undoManager?.beginUndoGrouping()
                    textView.replace(selectedTextRange, withText: checkbox.string)
                    textView.textStorage.replaceCharacters(in: NSRange(location: selectedRange.location, length: checkbox.length), with: checkbox)
                    textView.undoManager?.endUndoGrouping()
                #endif
                return
            }
        }

        // Autocomplete ordered and unordered lists

        if selectedRange.location != currentParagraphRange.location, currentParagraphRange.upperBound - 2 < selectedRange.location {
            if let charsMatch = TextFormatter.getAutocompleteCharsMatch(string: currentParagraph.string) {
                matchChars(string: currentParagraph, match: charsMatch)
                return
            }

            if let digitsMatch = TextFormatter.getAutocompleteDigitsMatch(string: currentParagraph.string) {
                matchDigits(string: currentParagraph, match: digitsMatch)
                return
            }
        }

        // New Line insertion

        var newLine = "\n"

        if currentParagraph.string.starts(with: "\t"), let prefix = currentParagraph.string.getPrefixMatchSequentially(char: "\t") {
            if selectedRange.location != currentParagraphRange.location {
                newLine += prefix
            }

            let string = TextFormatter.getAttributedCode(string: newLine)
            insertText(string)
            return
        }

        if currentParagraph.string.starts(with: "    "),
           let prefix = currentParagraph.string.getPrefixMatchSequentially(char: " ")
        {
            if selectedRange.location != currentParagraphRange.location {
                newLine += prefix
            }

            let string = TextFormatter.getAttributedCode(string: newLine)
            insertText(string)
            return
        }

        #if os(iOS)
            textView.insertText("\n")
        #else
            textView.insertNewline(nil)
        #endif
    }

    public func backTick() {
        let selectedRange = textView.selectedRange

        if selectedRange.length > 0 {
            let text = storage.attributedSubstring(from: selectedRange).string
            let string = "`\(text)`"

            if let codeFont = UserDefaultsManagement.codeFont {
                let mutableString = NSMutableAttributedString(string: string)
                mutableString.addAttribute(.font, value: codeFont, range: NSRange(0..<string.count))

                EditTextView.shouldForceRescan = true
                insertText(mutableString, replacementRange: selectedRange)
                return
            }
        }

        insertText("``")
        setSelectedRange(NSRange(location: selectedRange.location, length: selectedRange.length + 1))
    }

    public func codeBlock() {
        EditTextView.shouldForceRescan = true

        let currentRange = textView.selectedRange
        if currentRange.length > 0 {
            let substring = storage.attributedSubstring(from: currentRange)
            let mutable = NSMutableAttributedString(string: "```\n")
            mutable.append(substring)

            if substring.string.last != "\n" {
                mutable.append(NSAttributedString(string: "\n"))
            }

            mutable.append(NSAttributedString(string: "```\n"))

            insertText(mutable, replacementRange: currentRange)
            setSelectedRange(NSRange(location: currentRange.location + 3, length: 0))
            return
        }

        insertText("```\n\n```\n")
        setSelectedRange(NSRange(location: currentRange.location + 4, length: 0))
    }

    public func quote() {
        EditTextView.shouldForceRescan = true

        let currentRange = textView.selectedRange
        if currentRange.length > 0 {
            guard let pRange = getParagraphRange() else { return }

            let string = storage.attributedSubstring(from: pRange).string
            var lines = [String]()
            string.enumerateLines { line, _ in
                lines.append("> " + line)
            }

            let result = lines.joined(separator: "\n")
            insertText(result, replacementRange: pRange)
            return
        }

        guard let pRange = getParagraphRange() else { return }
        let paragraph = storage.mutableString.substring(with: pRange)

        insertText("> " + paragraph, replacementRange: pRange)
        setSelectedRange(NSRange(location: currentRange.location + 2, length: 0))
    }

    private func getAttributedTodoString(_ string: String) -> NSAttributedString {
        let string = NSMutableAttributedString(string: string)
        string.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: NSRange(0..<1))

        var color = Color.black
        #if os(OSX)
            if UserDefaultsManagement.appearanceType != AppearanceType.Custom, #available(OSX 10.13, *) {
                color = NSColor(named: "mainText")!
            }
        #endif

        string.addAttribute(.foregroundColor, value: color, range: NSRange(1..<string.length))
        return string
    }

    private func replaceWith(string: String, range: NSRange? = nil) {
        #if os(iOS)
            var selectedRange: UITextRange

            if let range = range,
               let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
               let end = textView.position(from: start, offset: range.length),
               let sRange = textView.textRange(from: start, to: end)
            {
                selectedRange = sRange
            } else {
                selectedRange = textView.selectedTextRange!
            }

            textView.undoManager?.beginUndoGrouping()
            textView.replace(selectedRange, withText: string)
            textView.undoManager?.endUndoGrouping()
        #else
            var r = textView.selectedRange
            if let range = range {
                r = range
            }

            textView.insertText(string, replacementRange: r)
        #endif
    }

    deinit {
        if note.isMarkdown() {
            if var font = UserDefaultsManagement.noteFont {
                #if os(iOS)
                    if #available(iOS 11.0, *), UserDefaultsManagement.dynamicTypeFont {
                        let fontMetrics = UIFontMetrics(forTextStyle: .body)
                        font = fontMetrics.scaledFont(for: font)
                    }
                #endif

                setTypingAttributes(font: font)
            }
        }

        if self.shouldScanMarkdown, let paragraphRange = getParagraphRange() {
            NotesTextProcessor.highlightMarkdown(attributedString: storage, paragraphRange: paragraphRange, note: note)
        }

        if note.isMarkdown() || note.type == .RichText {
            var text: NSAttributedString?

            #if os(OSX)
                text = textView.attributedString()
            #else
                text = textView.attributedText
            #endif

            if let attributed = text {
                note.save(attributed: attributed)
            }
        }

        #if os(iOS)
            textView.initUndoRedoButons()
        #endif
    }

    func getParagraphRange() -> NSRange? {
        if range.upperBound <= storage.length {
            let paragraph = storage.mutableString.paragraphRange(for: range)
            return paragraph
        }

        return nil
    }

    private func getParagraphRange(for location: Int) -> NSRange? {
        guard location <= storage.length else { return nil }

        let range = NSRange(location: location, length: 0)
        let paragraphRange = storage.mutableString.paragraphRange(for: range)

        return paragraphRange
    }

    func toggleBoldFont(font: Font) -> Font {
        if font.isBold {
            return font.unBold()
        } else {
            return font.bold()
        }
    }

    func toggleItalicFont(font: Font) -> Font {
        if font.isItalic {
            return font.unItalic()
        } else {
            return font.italic()
        }
    }

    func getTypingAttributes() -> Font {
        #if os(OSX)
            return textView.typingAttributes[.font] as! Font
        #else
            if let typingFont = textView.typingFont {
                textView.typingFont = nil
                return typingFont
            }

            guard textView.textStorage.length > 0, textView.selectedRange.location > 0 else { return getDefaultFont() }

            let i = textView.selectedRange.location - 1
            let upper = textView.selectedRange.upperBound
            let substring = textView.attributedText.attributedSubstring(from: NSRange(i..<upper))

            if let prevFont = substring.attribute(.font, at: 0, effectiveRange: nil) as? UIFont {
                return prevFont
            }

            return getDefaultFont()
        #endif
    }

    #if os(iOS)
        private func getDefaultFont() -> UIFont {
            var font = UserDefaultsManagement.noteFont!

            if #available(iOS 11.0, *), UserDefaultsManagement.dynamicTypeFont {
                let fontMetrics = UIFontMetrics(forTextStyle: .body)
                font = fontMetrics.scaledFont(for: font)
            }

            return font
        }
    #endif

    #if os(OSX)
        private func getDefaultColor() -> NSColor {
            var color = Color.black
            if UserDefaultsManagement.appearanceType != AppearanceType.Custom, #available(OSX 10.13, *) {
                color = NSColor(named: "mainText")!
            }
            return color
        }
    #endif

    func setTypingAttributes(font: Font) {
        #if os(OSX)
            textView.typingAttributes[.font] = font
        #else
            textView.typingFont = font
            textView.typingAttributes[.font] = font
        #endif
    }

    public func setSelectedRange(_ range: NSRange) {
        #if os(OSX)
            if range.upperBound <= storage.length {
                textView.setSelectedRange(range)
            }
        #else
            textView.selectedRange = range
        #endif
    }

    func getAttributedString() -> NSAttributedString {
        #if os(OSX)
            return textView.attributedString()
        #else
            return textView.attributedText
        #endif
    }

    public static func getCodeParagraphStyle() -> NSMutableParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(UserDefaultsManagement.editorLineSpacing)
        paragraphStyle.lineHeightMultiple = CGFloat(UserDefaultsManagement.editorLineHeight)
        #if os(OSX)
            paragraphStyle.textBlocks = [CodeBlock()]
        #endif

        return paragraphStyle
    }

    private func insertText(_ string: Any, replacementRange: NSRange? = nil, selectRange: NSRange? = nil) {
        let range = replacementRange ?? textView.selectedRange

        #if os(iOS)
            guard
                let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                let end = textView.position(from: start, offset: range.length),
                let selectedRange = textView.textRange(from: start, to: end)
            else { return }

            var replaceString = String()
            if let attributedString = string as? NSAttributedString {
                replaceString = attributedString.string
            }

            if let plainString = string as? String {
                replaceString = plainString
            }

            textView.undoManager?.beginUndoGrouping()
            textView.replace(selectedRange, withText: replaceString)

            let parRange = NSRange(location: range.location, length: replaceString.count)
            let parStyle = NSMutableParagraphStyle()
            parStyle.alignment = .left
            textView.textStorage.addAttribute(.paragraphStyle, value: parStyle, range: parRange)

            textView.undoManager?.endUndoGrouping()
        #else
            textView.insertText(string, replacementRange: range)
        #endif

        if let select = selectRange {
            setSelectedRange(select)
        }
    }

    public static func getAttributedCode(string: String) -> NSMutableAttributedString {
        let attributedString = NSMutableAttributedString(string: string)
        let range = NSRange(0..<attributedString.length)

        attributedString.addAttribute(.font, value: NotesTextProcessor.codeFont as Any, range: range)
        return attributedString
    }
}
