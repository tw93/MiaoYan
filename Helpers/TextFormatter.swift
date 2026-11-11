import Carbon.HIToolbox
import Cocoa
import Foundation
import MiaoYanCore

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
        guard let pRange = getParagraphRange() else { return }
        var padding = "  "

        let nsContent = storage.mutableString as NSString
        let beforeLineRange = getLineRangeBefore(str: nsContent, lineRange: pRange)
        if beforeLineRange != nil {
            let beforeText = storage.attributedSubstring(from: beforeLineRange!).string
            if beforeText.isNumberList() { padding = "   " }
        }
        guard range.length > 0 else {
            let original = storage.attributedSubstring(from: pRange).string
            var text = original
            if text.isNumberList() {
                text = ViewController.replace(validateString: text, regex: "^[0-9-]+[.]", content: "1.")
            }
            // Renumbering "10." to "1." shortens the line: past the number the caret
            // moves by the change in length, not the whole indent, or it left the line.
            let shrink = (original as NSString).length - (text as NSString).length
            let offset = textView.selectedRange().location - pRange.location
            textView.insertText(padding + text, replacementRange: pRange)
            setSelectedRange(NSRange(location: pRange.location + padding.count + max(min(offset, 2), offset - shrink), length: 0))
            return
        }

        let string = storage.attributedSubstring(from: pRange).string
        var lines = [String]()
        var num = 0
        string.enumerateLines { line, _ in
            var newLine = line
            if newLine.isNumberList() {
                num += 1
                newLine = ViewController.replace(validateString: newLine, regex: "^[0-9-]+[.]", content: "\(num).")
            }
            lines.append(padding + newLine)
        }

        var result = lines.joined(separator: "\n")
        if pRange.upperBound != storage.length { result += "\n" }

        if textView.textStorage?.length == 0 { EditTextView.shouldForceRescan = true }

        textView.insertText(result, replacementRange: pRange)
        setSelectedRange(NSRange(location: pRange.lowerBound, length: (result as NSString).length))
    }

    func unTab() {
        guard let pRange = getParagraphRange() else { return }
        guard range.length > 0 else {
            let text = storage.attributedSubstring(from: pRange).string
            let (newText, diff) = removeLeadingIndent(from: text)
            guard let processedText = newText else { return }

            let replacement: String
            if processedText.isEmpty {
                replacement = pRange.upperBound < storage.length ? "\n" : ""
            } else {
                replacement = processedText
            }
            textView.insertText(replacement, replacementRange: pRange)
            setSelectedRange(NSRange(location: range.location - diff, length: 0))
            return
        }

        let string = storage.attributedSubstring(from: pRange).string
        var resultList: [String] = []
        string.enumerateLines { line, _ in
            var processedLine = line
            if !processedLine.isEmpty {
                let (newLine, _) = self.removeLeadingIndent(from: processedLine)
                if let text = newLine {
                    processedLine = text
                }
            }
            resultList.append(processedLine)
        }

        var result = resultList.joined(separator: "\n")
        if pRange.upperBound != storage.length { result += "\n" }
        textView.insertText(result, replacementRange: pRange)
        let finalRange = NSRange(location: pRange.lowerBound, length: (result as NSString).length)
        setSelectedRange(finalRange)
    }

    private func removeLeadingIndent(from text: String) -> (String?, Int) {
        if text.starts(with: "   ") {
            return (String(text.dropFirst(3)), 3)
        } else if text.starts(with: "  ") {
            return (String(text.dropFirst(2)), 2)
        } else if text.starts(with: " ") {
            return (String(text.dropFirst()), 1)
        } else if text.starts(with: "\t") {
            return (String(text.dropFirst()), 1)
        }
        return (nil, 0)
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
        if range.length == 0 {
            setSelectedRange(NSRange(location: range.location + 1, length: 0))
        } else {
            setSelectedRange(NSRange(location: range.upperBound + 3, length: 0))
        }
    }

    public func image() {
        let text = "![" + attributedString.string + "]()"
        replaceWith(string: text)
        if range.length == 0 {
            setSelectedRange(NSRange(location: range.location + 2, length: 0))
        } else {
            setSelectedRange(NSRange(location: range.upperBound + 4, length: 0))
        }
    }

    /// The box of a task line ("  - [x] a", "1. [ ] b"), as a range inside
    /// the line: the one character between the brackets.
    static func taskBoxRange(in line: String) -> NSRange? {
        guard
            let regex = try? NSRegularExpression(pattern: "^[ \\t]*(?:[-*+]|[0-9]+[.)]) \\[([ xX])\\]"),
            let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        else { return nil }
        return match.range(at: 1)
    }

    public func toggleTodo() {
        guard let currentParagraphRange = getParagraphRange() else { return }
        let string = storage.attributedSubstring(from: currentParagraphRange).string

        guard let box = Self.taskBoxRange(in: string) else {
            insertText("- [ ] ", replacementRange: NSRange(location: currentParagraphRange.location, length: 0))
            return
        }
        let mark = (string as NSString).substring(with: box) == " " ? "x" : " "
        let selection = textView.selectedRange
        replaceWith(string: mark, range: NSRange(location: currentParagraphRange.location + box.location, length: 1))
        setSelectedRange(selection)
    }

    /// Markers only the Mac continues, on top of `ListContinuation`'s: the
    /// en dash, em dash and bullet a writer types by hand, and `| ` table rows.
    private static let macOnlyMarkerRegex = try? NSRegularExpression(pattern: "^[ \\t]*[\u{2013}\u{2014}\u{2022}|] ")

    /// Return at the end of a line starting with a Mac-only marker: the
    /// marker again, or on a line holding only the marker, the line emptied,
    /// with the same line ending and fenced-code rule as `ListContinuation`.
    /// The caret goes to the end of the replacement.
    static func macOnlyMarkerEdit(in text: NSString, caret: Int) -> (range: NSRange, replacement: String)? {
        guard caret >= 0, caret <= text.length, let regex = macOnlyMarkerRegex else { return nil }
        var start = 0
        var contentsEnd = 0
        text.getParagraphStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
        let line = NSRange(location: start, length: contentsEnd - start)
        guard caret == contentsEnd, caret > start, !ListContinuation.isInFencedCode(at: caret, in: text),
            let match = regex.firstMatch(in: text as String, range: line)
        else { return nil }
        if match.range.length == line.length { return (line, "") }
        return (NSRange(location: caret, length: 0), ListContinuation.lineBreak(in: text) + text.substring(with: match.range))
    }

    public func newLine() {
        guard let currentParagraphRange = getParagraphRange() else { return }
        let currentParagraph = storage.attributedSubstring(from: currentParagraphRange)
        let selectedRange = textView.selectedRange

        // Return with the caret at the end of a list or quote line runs the
        // rule the iPhone and iPad editor run (MiaoYanCore), so both write
        // the same marker, end a list the same way and skip fenced code.
        if selectedRange.length == 0 {
            let text = storage.string as NSString
            if let edit = ListContinuation.edit(in: text, caret: selectedRange.location) {
                insertText(edit.replacement, replacementRange: edit.range, selectRange: NSRange(location: edit.caret, length: 0))
                return
            }
            if let edit = Self.macOnlyMarkerEdit(in: text, caret: selectedRange.location) {
                let caret = edit.range.location + (edit.replacement as NSString).length
                insertText(edit.replacement, replacementRange: edit.range, selectRange: NSRange(location: caret, length: 0))
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
            // Inline code stays in the text font, like the highlighter draws it.
            EditTextView.shouldForceRescan = true
            insertText("`\(text)`", replacementRange: selectedRange)
            return
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
