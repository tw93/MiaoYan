import Cocoa

@MainActor
class EditorMenuManager {
    private weak var textView: EditTextView?

    init(textView: EditTextView) {
        self.textView = textView
    }

    /// The editor of the storyboard window. Replaced in tests.
    static var windowEditor: () -> EditTextView? = { ViewController.shared()?.editArea }

    /// The editor a command acts on. The storyboard's Format menu targets a
    /// stand-in EditTextView in the Application scene, which sits in no window
    /// and never has focus, so its commands go to the window's editor; the
    /// shell's editor is in a window and acts on itself.
    private var editor: EditTextView? {
        guard let textView else { return nil }
        if textView.window == nil, let windowEditor = Self.windowEditor() {
            return windowEditor
        }
        return textView
    }

    func performFormattingAction(_ action: FormattingAction) {
        guard let editArea = editor,
            let note = editArea.storageNote ?? EditTextView.note,
            editArea.hasFocus()
        else { return }
        if !editArea.isShellHosted, let vc = ViewController.shared(),
            vc.sessionPreviewMode || vc.sessionPresentationMode || vc.sessionMagicPPTMode
        {
            return
        }

        let formatter = TextFormatter(textView: editArea, note: note, shouldScanMarkdown: action.shouldScanMarkdown)

        switch action {
        case .bold:
            formatter.bold()
        case .italic:
            formatter.italic()
        case .link:
            formatter.link()
        case .todo:
            formatter.toggleTodo()
        case .underline:
            formatter.underline()
        case .deleteline:
            formatter.deleteline()
        case .inlineCode:
            formatter.backTick()
        case .codeBlock:
            formatter.codeBlock()
        }
    }

    func insertCodeBlock() {
        guard let textView = editor else { return }

        let currentRange = textView.selectedRange()

        if currentRange.length > 0 {
            let mutable = NSMutableAttributedString(string: "```\n")
            if let substring = textView.attributedSubstring(forProposedRange: currentRange, actualRange: nil) {
                mutable.append(substring)

                if substring.string.last != Character("\n") {
                    mutable.append(NSAttributedString(string: "\n"))
                }
            }

            mutable.append(NSAttributedString(string: "```\n"))

            EditTextView.shouldForceRescan = true
            textView.insertText(mutable, replacementRange: currentRange)
            textView.setSelectedRange(NSRange(location: currentRange.location + 3, length: 0))
            return
        }

        if textView.textStorage?.length == 0 {
            EditTextView.shouldForceRescan = true
        }

        textView.insertText("```\n\n```\n", replacementRange: currentRange)
        textView.setSelectedRange(NSRange(location: currentRange.location + 3, length: 0))
    }

    func insertCodeSpan() {
        guard let textView = editor else { return }

        let currentRange = textView.selectedRange()

        if currentRange.length > 0 {
            let mutable = NSMutableAttributedString(string: "`")
            if let substring = textView.attributedSubstring(forProposedRange: currentRange, actualRange: nil) {
                mutable.append(substring)
            }

            mutable.append(NSAttributedString(string: "`"))

            EditTextView.shouldForceRescan = true
            textView.insertText(mutable, replacementRange: currentRange)
            return
        }

        textView.insertText("``", replacementRange: currentRange)
        textView.setSelectedRange(NSRange(location: currentRange.location + 1, length: 0))
    }

    func insertFileOrImage() {
        guard let note = EditTextView.note else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = true

        panel.begin { result in
            if result == NSApplication.ModalResponse.OK {
                self.handleFileSelection(urls: panel.urls, note: note)
            }
        }
    }

    private func handleFileSelection(urls: [URL], note: Note) {
        guard let textView = editor else { return }

        let clipboardManager = ClipboardManager(textView: textView)
        let last = urls.last

        for url in urls {
            if clipboardManager.saveFile(url: url, in: note) {
                if last != url {
                    textView.insertNewline(nil)
                    if let vc = ViewController.shared() {
                        vc.notesTableView.reloadRow(note: note)
                    }
                }
            }

            if url != urls.last {
                textView.insertNewline(nil)
            }
        }
    }

    func togglePreview() {
        guard let vc = ViewController.shared() else { return }
        vc.togglePreview()
    }

    func formatText() {
        guard let vc = ViewController.shared() else { return }
        vc.formatText()
    }

    func cleanTypography() {
        guard let vc = ViewController.shared() else { return }
        vc.cleanTypography(nil)
    }

    func togglePresentation() {
        guard let vc = ViewController.shared() else { return }
        vc.togglePresentation()
    }

    func toggleTOC() {
        guard let vc = ViewController.shared() else { return }
        vc.toggleTOC(self)
    }
}

enum FormattingAction {
    case bold
    case italic
    case link
    case todo
    case underline
    case deleteline
    case inlineCode
    case codeBlock

    var shouldScanMarkdown: Bool {
        switch self {
        case .todo:
            return false
        default:
            return true
        }
    }
}
