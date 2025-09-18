import Cocoa

@MainActor
class EditorMenuManager {
    private weak var textView: EditTextView?

    init(textView: EditTextView) {
        self.textView = textView
    }

    func performFormattingAction(_ action: FormattingAction) {
        guard textView != nil,
            let vc = ViewController.shared(),
            let editArea = vc.editArea,
            let note = EditTextView.note,
            !UserDefaultsManagement.preview,
            editArea.hasFocus()
        else { return }

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
        }
    }

    func insertCodeBlock() {
        guard let textView = textView else { return }

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
        guard let textView = textView else { return }

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
        guard let textView = textView else { return }

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

    func togglePresentation() {
        guard let vc = ViewController.shared() else { return }
        vc.togglePresentation()
    }
}

enum FormattingAction {
    case bold
    case italic
    case link
    case todo
    case underline
    case deleteline

    var shouldScanMarkdown: Bool {
        switch self {
        case .todo:
            return false
        default:
            return true
        }
    }
}
