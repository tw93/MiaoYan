import Carbon.HIToolbox
import Cocoa

class TitleTextField: NSTextField {
    public var vcDelegate: ViewController!
    public var restoreResponder: NSResponder?

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func layout() {
        super.layout()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let pasteboard = NSPasteboard.general

        if event.modifierFlags.contains(.command),
            event.keyCode == kVK_ANSI_C,
            let selectedRange = currentEditor()?.selectedRange,
            selectedRange.length > 0
        {
            // Processing copy commands
            let selectedString = (stringValue as NSString).substring(with: selectedRange)
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(selectedString, forType: NSPasteboard.PasteboardType.string)
        }

        // Checks if Command + V was pressed and the current NSTextField is the first responder.
        if event.modifierFlags.contains(.command),
            event.keyCode == kVK_ANSI_V,
            window?.firstResponder == currentEditor()
        {
            if let items = pasteboard.pasteboardItems {
                for item in items {
                    if let string = item.string(forType: .string) {
                        let noNewlineString = string.replacingOccurrences(of: "\n", with: " ")
                        pasteboard.clearContents()
                        pasteboard.setString(noNewlineString, forType: .string)
                    }
                }
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        // 保持当前显示的标题作为编辑的起始值，不需要重新设置
        return super.becomeFirstResponder()
    }

    override func textDidEndEditing(_ notification: Notification) {
        saveTitle()
    }

    public func saveTitle() {
        guard let vc = ViewController.shared(), let note = EditTextView.note else {
            return
        }

        // 允许空标题的情况（UUID文件名显示为空）
        guard stringValue.count > 0 else {
            // 对于空标题，无需做任何操作，保持当前显示状态
            return
        }

        let currentTitle = stringValue.trimmingCharacters(in: NSCharacterSet.newlines)
        let currentName = note.getFileName()

        if currentName != currentTitle {
            let ext = note.url.pathExtension
            let fileName =
                currentTitle
                .trimmingCharacters(in: CharacterSet.whitespaces)
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: "/", with: ":")
            let dst = note.project.url.appendingPathComponent(fileName).appendingPathExtension(ext)

            // 允许仅大小写变化时重命名
            let isCaseOnlyChange = currentName.lowercased() == currentTitle.lowercased() && currentName != currentTitle

            if (!FileManager.default.fileExists(atPath: dst.path) || isCaseOnlyChange) && note.move(to: dst) {
                note.title = currentTitle
                vc.updateTitle(newTitle: currentTitle)
                updateNotesTableView()
            } else {
                vc.updateTitle(newTitle: currentTitle)
                resignFirstResponder()
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.informativeText = String(format: NSLocalizedString("This %@ under this folder already exists!", comment: ""), currentTitle)
                alert.messageText = NSLocalizedString("Please change the title", comment: "")
                alert.runModal()
            }
        }
    }

    public func hasFocus() -> Bool {
        var inFocus = false
        inFocus = (window?.firstResponder is NSTextView) && window?.fieldEditor(false, for: nil) != nil && isEqual(to: (window?.firstResponder as? NSTextView)?.delegate)
        return inFocus
    }

    public func editModeOn() {
        MainWindowController.shared()?.makeFirstResponder(self)
    }

    public func updateNotesTableView() {
        guard let vc = ViewController.shared(), let note = EditTextView.note else { return }

        let currentTitle = note.title
        vc.notesTableView.reloadRow(note: note)
        if !currentTitle.isEmpty {
            note.title = currentTitle
        }
    }
}
