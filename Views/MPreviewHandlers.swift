import Cocoa
import MiaoYanCore
import WebKit

class HandlerTOCTip: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        UserDefaultsManagement.hasShownTOCTip = true
    }
}
class HandlerCheckbox: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let position = message.body as? String else { return }
        // Toggle the note the preview shows, which can trail the list
        // selection while a render is still landing.
        let preview = message.webView as? MPreviewView
        guard let note = preview?.displayedNote ?? EditTextView.note else { return }
        note.ensureContentLoaded()
        let text = note.content.unLoadCheckboxes().unLoadImages().string

        guard position.hasPrefix("line:"), let bodyLine = Int(position.dropFirst(5)),
            let range = HandlerCheckbox.taskMarkerRange(in: text, bodyLine: bodyLine)
        else { return }
        let marker = (text as NSString).substring(with: range)
        let toggled = marker == " " ? "x" : " "

        // An editable editor holding this note takes the edit itself, so the
        // next keystroke cannot copy the old buffer back over the toggle. In
        // preview mode the editor is read-only and would drop the insert.
        if let editor = preview?.window.flatMap(HandlerCheckbox.editor(in:)), editor.isEditable,
            editor.storageNote === note, editor.string == text
        {
            editor.insertText(toggled, replacementRange: range)
            return
        }
        let updated = NSMutableAttributedString(string: text)
        updated.replaceCharacters(in: range, with: toggled)
        note.save(content: updated)
    }

    /// The range of the space or x inside `[ ]` on the task item at
    /// `bodyLine` (1-based, counted after the frontmatter the preview drops).
    nonisolated static func taskMarkerRange(in text: String, bodyLine: Int) -> NSRange? {
        let target = Frontmatter.lineCount(of: text) + bodyLine - 1
        let ns = text as NSString
        // cmark's source lines end only at \n, \r\n or \r. NSString.lineRange
        // also breaks at U+2028, U+2029 and U+0085, which text pasted from the
        // web carries, and then counted to the wrong task.
        func lineEnd(from start: Int) -> (end: Int, next: Int) {
            var index = start
            while index < ns.length {
                let unit = ns.character(at: index)
                if unit == 0x0A { return (index, index + 1) }
                if unit == 0x0D {
                    let crlf = index + 1 < ns.length && ns.character(at: index + 1) == 0x0A
                    return (index, index + (crlf ? 2 : 1))
                }
                index += 1
            }
            return (ns.length, ns.length)
        }
        var lineStart = 0
        for _ in 0..<max(target, 0) {
            let next = lineEnd(from: lineStart).next
            guard next < ns.length else { return nil }
            lineStart = next
        }
        let line = NSRange(location: lineStart, length: lineEnd(from: lineStart).end - lineStart)
        guard
            let match = taskItemRegex.firstMatch(in: text, range: line),
            match.range(at: 1).location != NSNotFound
        else { return nil }
        return match.range(at: 1)
    }

    nonisolated private static let taskItemRegex = try! NSRegularExpression(pattern: #"^[ \t>]*(?:[-*+]|\d+[.)])[ \t]+\[([ xX])\]"#, options: [.anchorsMatchLines])

    private static func editor(in window: NSWindow) -> EditTextView? {
        var stack: [NSView] = window.contentView.map { [$0] } ?? []
        while let view = stack.popLast() {
            if let editor = view as? EditTextView { return editor }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }
}

class HandlerCodeCopy: NSObject, WKScriptMessageHandler {
    public static var selectionString: String? {
        didSet {
            guard let copyBlock = selectionString else {
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyBlock, forType: .string)
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let message = (message.body as! String).trimmingCharacters(in: .whitespacesAndNewlines)
        HandlerCodeCopy.selectionString = message
    }
}

class HandlerSelection: NSObject, WKScriptMessageHandler {
    public static var selectionString: String?
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let message = (message.body as! String).trimmingCharacters(in: .whitespacesAndNewlines)
        HandlerSelection.selectionString = message
    }
}
// Used to solve the adaptation of the left border/title color change with background color in PPT mode.

class HandlerRevealBackgroundColor: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let vc = AppContext.shared.viewController else { return }
        let message = (message.body as! String).trimmingCharacters(in: .whitespacesAndNewlines)
        if message == "" {
            vc.titleLabel.backgroundColor = Theme.backgroundColor
        } else {
            vc.sidebarSplitView.setValue(NSColor(css: message), forKey: "dividerColor")
            vc.splitView.setValue(NSColor(css: message), forKey: "dividerColor")
        }
    }
}

class HandlerPreviewScroll: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let previewView = message.webView as? MPreviewView else {
            return
        }

        guard let dict = message.body as? [String: Any],
            let lineNum = (dict["line"] as? NSNumber)?.doubleValue
        else { return }
        Task { @MainActor in
            previewView.scrollDelegate?.previewDidScroll(line: CGFloat(lineNum))
        }
    }
}
