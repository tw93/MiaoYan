import Carbon.HIToolbox
import Cocoa

class TitleTextField: NSTextField {
    public var vcDelegate: ViewController!
    public var restoreResponder: NSResponder?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.keyCode == kVK_ANSI_C,
           !event.modifierFlags.contains(.shift),
           !event.modifierFlags.contains(.control),
           !event.modifierFlags.contains(.option) {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(self.stringValue, forType: NSPasteboard.PasteboardType.string)
        }

        return super.performKeyEquivalent(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        if let note = EditTextView.note {
            stringValue = note.getShortTitle()
        }
        return super.becomeFirstResponder()
    }

    override func textDidEndEditing(_ notification: Notification) {
        saveTitle()
    }

    public func saveTitle() {
        guard stringValue.count > 0, let vc = ViewController.shared(), let note = EditTextView.note else { return }

        let currentTitle = stringValue.trimmingCharacters(in: NSCharacterSet.newlines)
        let currentName = note.getFileName()

        defer {
            updateNotesTableView()
        }

        if currentName != currentTitle {
            let ext = note.url.pathExtension
            let fileName =
                    currentTitle
                            .trimmingCharacters(in: CharacterSet.whitespaces)
                            .replacingOccurrences(of: ":", with: "-")
                            .replacingOccurrences(of: "/", with: ":")
            let dst = note.project.url.appendingPathComponent(fileName).appendingPathExtension(ext)

            if !FileManager.default.fileExists(atPath: dst.path), note.move(to: dst) {
                vc.updateTitle(newTitle: currentTitle)
                updateNotesTableView()
                vc.reSort(note: note)
            } else {
                vc.updateTitle(newTitle: currentTitle)
                resignFirstResponder()
                updateNotesTableView()
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.informativeText = String(format: NSLocalizedString("This %@ under this folder already exists!", comment: ""), currentTitle)
                alert.messageText = NSLocalizedString("Please change the title", comment: "")
                alert.runModal()
            }
        } else {
            vc.updateTitle(newTitle: currentTitle)
            resignFirstResponder()
            updateNotesTableView()
        }
    }

    public func hasFocus() -> Bool {
        var inFocus = false
        inFocus = (self.window?.firstResponder is NSTextView) && self.window?.fieldEditor(false, for: nil) != nil && self.isEqual(to: (self.window?.firstResponder as? NSTextView)?.delegate)
        return inFocus
    }

    public func editModeOn() {
        MainWindowController.shared()?.makeFirstResponder(self)
    }

    public func updateNotesTableView() {
        guard let vc = ViewController.shared(), let note = EditTextView.note else { return }
        vc.notesTableView.reloadRow(note: note)
        if let responder = restoreResponder {
            window?.makeFirstResponder(responder)
        }
    }
}
