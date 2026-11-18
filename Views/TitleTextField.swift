import Carbon.HIToolbox
import Cocoa

@MainActor
class TitleTextField: NSTextField, NSTextFieldDelegate {
    public var vcDelegate: ViewController!
    public var restoreResponder: NSResponder?

    override class var cellClass: AnyClass? {
        get { TitleTextFieldCell.self }
        set { super.cellClass = newValue }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.keyCode == kVK_ANSI_C {
            handleCopy(pb: NSPasteboard.general)
        }

        return super.performKeyEquivalent(with: event)
    }

    private func handleCopy(pb: NSPasteboard) {
        guard let range = currentEditor()?.selectedRange,
            range.length > 0
        else { return }

        let text = (stringValue as NSString).substring(with: range)
        pb.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
        pb.setString(text, forType: NSPasteboard.PasteboardType.string)
    }

    /// The first non-empty line of multi-line text, without its outer spaces.
    nonisolated static func titleLine(from text: String) -> String {
        let line = text.components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return line?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// The title has its own field editor (`TitleFieldEditor`), so focus is
    /// any text view editing on its behalf, not only the window's shared one.
    public func hasFocus() -> Bool {
        guard let editor = window?.firstResponder as? NSTextView else { return false }
        return isEqual(to: editor.delegate)
    }

    public func editModeOn() {
        MainWindowController.shared()?.makeFirstResponder(self)
    }

    public func setStringValueSafely(_ value: String) {
        stringValue = value
    }

    public func updateNotesTableView() {
        guard let vc = AppContext.shared.viewController,
            let note = vc.notesTableView.getSelectedNote()
        else { return }

        vc.notesTableView.reloadRow(note: note)
        vc.titleLabel.isEditable = true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.delegate = self
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // TAB handling is done in ViewController's keyDown method
        return false
    }
}

/// Gives the title its own field editor, so every way text gets in (Cmd+V,
/// Edit > Paste, the context menu, a drop) passes through one filter.
final class TitleTextFieldCell: NSTextFieldCell {
    private var titleEditor: TitleFieldEditor?

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        if let titleEditor { return titleEditor }
        let editor = TitleFieldEditor()
        editor.isFieldEditor = true
        titleEditor = editor
        return editor
    }
}

/// Text with line breaks going into the title keeps only its first non-empty
/// line. A whole note pasted here used to become one huge title whose rename
/// failed and whose alert grew taller than the screen, hiding its only button.
/// Single-line text goes in as it is, and the clipboard is never touched.
final class TitleFieldEditor: NSTextView {
    override func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        guard let text = replacementString, text.contains(where: \.isNewline) else {
            return super.shouldChangeText(in: range, replacementString: replacementString)
        }

        let line = TitleTextField.titleLine(from: text)
        if !line.isEmpty, super.shouldChangeText(in: range, replacementString: line) {
            replaceCharacters(in: range, with: line)
            didChangeText()
            setSelectedRange(NSRange(location: range.location + line.utf16.count, length: 0))
        }
        return false
    }
}
