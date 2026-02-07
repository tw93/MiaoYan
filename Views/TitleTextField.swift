import Carbon.HIToolbox
import Cocoa

@MainActor
class TitleTextField: NSTextField, NSTextFieldDelegate {
    public var vcDelegate: ViewController!
    public var restoreResponder: NSResponder?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleClipboard(with: event)
        return super.performKeyEquivalent(with: event)
    }

    private func handleClipboard(with event: NSEvent) {
        let pb = NSPasteboard.general

        if event.modifierFlags.contains(.command) && event.keyCode == kVK_ANSI_C {
            handleCopy(pb: pb)
        }

        if event.modifierFlags.contains(.command) && event.keyCode == kVK_ANSI_V {
            handlePaste(pb: pb)
        }
    }

    private func handleCopy(pb: NSPasteboard) {
        guard let range = currentEditor()?.selectedRange,
            range.length > 0
        else { return }

        let text = (stringValue as NSString).substring(with: range)
        pb.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
        pb.setString(text, forType: NSPasteboard.PasteboardType.string)
    }

    private func handlePaste(pb: NSPasteboard) {
        guard window?.firstResponder == currentEditor(),
            let items = pb.pasteboardItems
        else { return }

        for item in items {
            if let text = item.string(forType: .string) {
                let cleanText = text.replacingOccurrences(of: "\n", with: " ")
                pb.clearContents()
                pb.setString(cleanText, forType: .string)
            }
        }
    }

    public func hasFocus() -> Bool {
        return (window?.firstResponder is NSTextView) && window?.fieldEditor(false, for: nil) != nil && isEqual(to: (window?.firstResponder as? NSTextView)?.delegate)
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
