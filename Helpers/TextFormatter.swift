import Carbon.HIToolbox
import Cocoa
import Foundation

typealias Font = NSFont
typealias TextView = EditTextView
typealias Color = NSColor

@MainActor
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

        storage = textView.textStorage!
        attributedSelected = textView.attributedString()
        if textView.typingAttributes[.font] == nil {
            textView.typingAttributes[.font] = UserDefaultsManagement.noteFont
        }

        attributedString = NSMutableAttributedString(attributedString: attributedSelected.attributedSubstring(from: range))
        selectedRange = NSRange(0..<attributedString.length)

        type = note.type
        self.textView = textView
        self.note = note

        prevSelectedRange = range
        prevSelectedString = storage.attributedSubstring(from: prevSelectedRange)

        self.shouldScanMarkdown = note.isMarkdown() ? shouldScanMarkdown : false
    }

    func getString() -> NSMutableAttributedString { attributedString }

    func bold() {
        if note.isMarkdown() {
            let string = "**" + attributedString.string + "**"
            let location = string.count == 4 ? range.location + 2 : range.upperBound + 4
            insertText(string, selectRange: NSRange(location: location, length: 0))
        }
    }

    func italic() {
        if note.isMarkdown() {
            let string = "*" + attributedString.string + "*"
            let location = string.count == 2 ? range.location + 1 : range.upperBound + 2
            insertText(string, selectRange: NSRange(location: location, length: 0))
        }
    }

    public func underline() {
        if note.isMarkdown() {
            let string = "<u>" + attributedString.string + "</u>"
            let location = string.count == 7 ? range.location + 3 : range.upperBound + 7
            insertText(string, selectRange: NSRange(location: location, length: 0))
        }
    }

    public func deleteline() {
        if note.isMarkdown() {
            let string = "~~" + attributedString.string + "~~"
            let location = string.count == 4 ? range.location + 2 : range.upperBound + 4
            insertText(string, selectRange: NSRange(location: location, length: 0))
        }
    }

    public func tab() {
        guard let vc = ViewController.shared() else { return }
        guard let pRange = getParagraphRange() else { return }
        var padding = "  "

        let nsContent = storage.mutableString as NSString
        let beforeLineRange = getLineRangeBefore(str: nsContent, lineRange: pRange)
        if beforeLineRange != nil {
            let beforeText = storage.attributedSubstring(from: beforeLineRange!).string
            if beforeText.isNumberList() { padding = "   " }
        }
        guard range.length > 0 else {
            var text = storage.attributedSubstring(from: pRange).string
            if text.isNumberList() {
                text = vc.replace(validateString: text, regex: "^[0-9-]+[.]", content: "1.")
            }
            let location = textView.selectedRange().location
            textView.insertText(padding + text, replacementRange: pRange)
            setSelectedRange(NSRange(location: location + padding.count, length: 0))
            return
        }

        let string = storage.attributedSubstring(from: pRange).string
        var lines = [String]()
        var num = 0
        string.enumerateLines { line, _ in
            var newLine = line
            if newLine.isNumberList() {
                num += 1
                newLine = vc.replace(validateString: newLine, regex: "^[0-9-]+[.]", content: "\(num).")
            }
            lines.append(padding + newLine)
        }

        var result = lines.joined(separator: "\n")
        if pRange.upperBound != storage.length { result += "\n" }

        if textView.textStorage?.length == 0 { EditTextView.shouldForceRescan = true }

        textView.insertText(result, replacementRange: pRange)
        setSelectedRange(NSRange(location: pRange.lowerBound, length: result.count))
    }

    func unTab() {
        guard let pRange = getParagraphRange() else { return }
        guard range.length > 0 else {
            var diff = 0
            var text = storage.attributedSubstring(from: pRange).string
            if text.starts(with: "   ") {
                diff = 3
                text = String(text.dropFirst(3))
            } else if text.starts(with: "  ") {
                diff = 2
                text = String(text.dropFirst(2))
            } else if text.starts(with: " ") {
                diff = 1
                text = String(text.dropFirst())
            } else if text.starts(with: "\t") {
                diff = 1
                text = String(text.dropFirst())
            } else {
                return
            }

            guard !text.isEmpty else { return }
            textView.insertText(text, replacementRange: pRange)
            setSelectedRange(NSRange(location: range.location - diff, length: 0))
            return
        }

        let string = storage.attributedSubstring(from: pRange).string
        var resultList: [String] = []
        string.enumerateLines { line, _ in
            var line = line
            if !line.isEmpty {
                if line.first == "\t" { line = String(line.dropFirst()) } else if line.starts(with: "   ") { line = String(line.dropFirst(3)) } else if line.starts(with: "  ") { line = String(line.dropFirst(2)) }
                    else if line.starts(with: " ") { line = String(line.dropFirst()) }
            }
            resultList.append(line)
        }

        var result = resultList.joined(separator: "\n")
        if pRange.upperBound != storage.length { result += "\n" }
        textView.insertText(result, replacementRange: pRange)
        let finalRange = NSRange(location: pRange.lowerBound, length: result.count)
        setSelectedRange(finalRange)
    }

    public func header(_ string: String) {
        guard let pRange = getParagraphRange() else { return }
        let selected = textView.selectedRange
        let paragraph = storage.mutableString.substring(with: pRange)
        let prefix = string + " "
        let selectRange = NSRange(location: selected.location + selected.length + prefix.count, length: 0)
        insertText(prefix + paragraph, replacementRange: pRange, selectRange: selectRange)
    }

    public func link() {
        let text = "[" + attributedString.string + "]()"
        replaceWith(string: text, range: range)
        if attributedString.length == 4 {
            setSelectedRange(NSRange(location: range.location + 1, length: 0))
        } else {
            setSelectedRange(NSRange(location: range.upperBound + 3, length: 0))
        }
    }

    public func image() {
        let text = "![" + attributedString.string + "]()"
        replaceWith(string: text)
        if attributedString.length == 5 {
            setSelectedRange(NSRange(location: range.location + 2, length: 0))
        } else {
            setSelectedRange(NSRange(location: range.upperBound + 4, length: 0))
        }
    }

    public func tabKey() {
        guard let currentPR = getParagraphRange() else { return }
        let paragraph = storage.attributedSubstring(from: currentPR).string
        let sRange = textView.selectedRange

        if sRange.location != 0 || sRange.location != storage.length,
            paragraph.count == 1, note.isMarkdown()
        {
            insertText("\t", replacementRange: sRange)
            return
        }

        if sRange.location == 0 || sRange.location == storage.length,
            paragraph.isEmpty, note.isMarkdown()
        {
            if textView.textStorage?.length == 0 { EditTextView.shouldForceRescan = true }
            insertText("\t\n", replacementRange: sRange)
            setSelectedRange(NSRange(location: sRange.location + 1, length: 0))
            return
        }

        insertText("\t")
    }

    public static func getAutocompleteCharsMatch(string: String) -> NSTextCheckingResult? {
        guard
            let regex = try? NSRegularExpression(
                pattern: "^(( |\\t)*\\- \\[[x| ]*\\] )|^(( |\\t)*[-|–|—|*|•|>|\\+]{1} )"),
            let result = regex.firstMatch(in: string, range: NSRange(0..<string.count))
        else { return nil }
        return result
    }

    public static func getAutocompleteDigitsMatch(string: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: "^(( |\\t)*[0-9]+\\. )"),
            let result = regex.firstMatch(in: string, range: NSRange(0..<string.count))
        else { return nil }
        return result
    }

    private func matchChars(string: NSAttributedString, match: NSTextCheckingResult, prefix: String? = nil) {
        guard string.length >= match.range.upperBound else { return }
        let found = string.attributedSubstring(from: match.range).string
        var newLine = 1
        if textView.selectedRange.upperBound == storage.length { newLine = 0 }
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
        if textView.selectedRange.upperBound == storage.length { newLine = 0 }
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

    public func toggleTodo() {
        guard let currentParagraphRange = getParagraphRange() else { return }
        let currentParagraph = storage.attributedSubstring(from: currentParagraphRange)
        let string = currentParagraph.string
        var todoString = "- [ ] "
        if string.contains("- [ ] ") { todoString = "- [x] " }

        if string.contains("- [ ] ") || string.contains("- [x] ") {
            replaceWith(string: todoString, range: NSRange(location: currentParagraphRange.location, length: 6))
        } else {
            insertText(todoString, replacementRange: NSRange(location: currentParagraphRange.location, length: 0))
        }
    }

    public func newLine() {
        guard let currentParagraphRange = getParagraphRange() else { return }
        let currentParagraph = storage.attributedSubstring(from: currentParagraphRange)
        let selectedRange = textView.selectedRange

        if selectedRange.location != currentParagraphRange.location,
            currentParagraphRange.upperBound - 2 < selectedRange.location,
            currentParagraph.length >= 2
        {
            if textView.selectedRange.upperBound > 2 {
                let char = storage.attributedSubstring(from: NSRange(location: textView.selectedRange.upperBound - 2, length: 1))
                if char.attribute(.todo, at: 0, effectiveRange: nil) != nil {
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
                let string = NSMutableAttributedString(string: "\n" + prefix)
                insertText(string)
                return
            }
        }

        if selectedRange.location != currentParagraphRange.location,
            currentParagraphRange.upperBound - 2 < selectedRange.location
        {
            if let charsMatch = TextFormatter.getAutocompleteCharsMatch(string: currentParagraph.string) {
                matchChars(string: currentParagraph, match: charsMatch)
                return
            }
            if let digitsMatch = TextFormatter.getAutocompleteDigitsMatch(string: currentParagraph.string) {
                matchDigits(string: currentParagraph, match: digitsMatch)
                return
            }
        }

        var newLine = "\n"

        if currentParagraph.string.starts(with: "\t"),
            let prefix = currentParagraph.string.getPrefixMatchSequentially(char: "\t")
        {
            if selectedRange.location != currentParagraphRange.location { newLine += prefix }
            let string = TextFormatter.getAttributedCode(string: newLine)
            insertText(string)
            return
        }

        if currentParagraph.string.starts(with: "  "),
            let prefix = currentParagraph.string.getPrefixMatchSequentially(char: " ")
        {
            if selectedRange.location != currentParagraphRange.location { newLine += prefix }
            let string = TextFormatter.getAttributedCode(string: newLine)
            insertText(string)
            return
        }

        textView.insertNewline(nil)
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

            if substring.string.last != "\n" { mutable.append(NSAttributedString(string: "\n")) }
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
            string.enumerateLines { line, _ in lines.append("> " + line) }

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
        let color: Color = Theme.textColor
        string.addAttribute(.foregroundColor, value: color, range: NSRange(1..<string.length))
        return string
    }

    private func replaceWith(string: String, range: NSRange? = nil) {
        var r = textView.selectedRange
        if let range { r = range }
        textView.insertText(string, replacementRange: r)
    }

    // ----------------------------
    // MARK: deinit
    // ----------------------------

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

    func toggleBoldFont(font: Font) -> Font { font.isBold ? font.unBold() : font.bold() }
    func toggleItalicFont(font: Font) -> Font { font.isItalic ? font.unItalic() : font.italic() }

    func getTypingAttributes() -> Font {
        textView.typingAttributes[.font] as! Font
    }

    private func getDefaultColor() -> NSColor { Theme.textColor }

    func setTypingAttributes(font: Font) { textView.typingAttributes[.font] = font }

    public func setSelectedRange(_ range: NSRange) {
        if range.upperBound <= storage.length { textView.setSelectedRange(range) }
    }

    func getAttributedString() -> NSAttributedString { textView.attributedString() }

    private func insertText(_ string: Any, replacementRange: NSRange? = nil, selectRange: NSRange? = nil) {
        let range = replacementRange ?? textView.selectedRange
        textView.insertText(string, replacementRange: range)
        if let select = selectRange { setSelectedRange(select) }
    }

    public static func getAttributedCode(string: String) -> NSMutableAttributedString {
        let attributedString = NSMutableAttributedString(string: string)
        let range = NSRange(0..<attributedString.length)
        if let fontValue = NotesTextProcessor.codeFont {
            attributedString.addAttribute(.font, value: fontValue as Any, range: range)
        }
        return attributedString
    }

    public func getLineRangeBefore(str: NSString, lineRange: NSRange) -> NSRange? {
        var lineStart = 0
        str.getLineStart(&lineStart, end: nil, contentsEnd: nil, for: lineRange)
        if lineStart == 0 { return nil }
        return str.lineRange(for: NSRange(location: lineStart - 1, length: 0))
    }
}
