import Carbon.HIToolbox
import Cocoa

@MainActor
class SearchTextField: NSSearchField, NSSearchFieldDelegate {
    public var vcDelegate: ViewController!

    private var filterQueue = OperationQueue()
    private var searchTimer = Timer()

    public var searchQuery = ""
    public var selectedRange = NSRange()
    public var skipAutocomplete = false

    public var timestamp: Int64?
    private var lastQueryLength: Int = 0

    private var trackingArea: NSTrackingArea?

    override func awakeFromNib() {
        super.awakeFromNib()
        sendsWholeSearchString = false
        sendsSearchStringImmediately = true

        // Remove cancel button
        if let searchFieldCell = self.cell as? NSSearchFieldCell {
            searchFieldCell.cancelButtonCell = nil
        }
    }

    override func rectForSearchText(whenCentered isCentered: Bool) -> NSRect {
        var rect = super.rectForSearchText(whenCentered: isCentered)
        rect.origin.y += 1.0
        rect.size.height += 2.0
        return rect
    }

    override func updateTrackingAreas() {
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }

    override var cancelButtonBounds: NSRect {
        NSRect.zero
    }

    override func textDidEndEditing(_ notification: Notification) {
        clearSelection()
        super.textDidEndEditing(notification)
    }

    private func clearSelection() {
        guard let editor = currentEditor(),
            editor.selectedRange.length > 0
        else { return }
        editor.replaceCharacters(in: editor.selectedRange, with: "")
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == kVK_DownArrow {
            vcDelegate.focusTable()
            vcDelegate.notesTableView.selectNext()
            return
        }

        if event.keyCode == kVK_LeftArrow && stringValue.isEmpty {
            vcDelegate.storageOutlineView.window?.makeFirstResponder(vcDelegate.storageOutlineView)
            vcDelegate.storageOutlineView.selectRowIndexes([1], byExtendingSelection: false)
            return
        }

        if event.keyCode == kVK_Return {
            vcDelegate.focusEditArea()
        }

        if event.keyCode == kVK_Delete || event.keyCode == kVK_ForwardDelete {
            skipAutocomplete = true
            return
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector.description {
        case "moveDown:":
            if let editor = currentEditor() {
                let query = editor.string.prefix(editor.selectedRange.location)
                if query.isEmpty {
                    return false
                }
                stringValue = String(query)
            }
            return true
        case "cancelOperation:":
            stringValue = ""
            vcDelegate.cleanSearchAndRestoreSelection()
            return true
        case "deleteBackward:":
            skipAutocomplete = true
            textView.deleteBackward(self)
            return true
        case "insertNewline:", "insertNewlineIgnoringFieldEditor:":
            if let note = vcDelegate.editArea.getSelectedNote(), !stringValue.isEmpty, note.title.lowercased().starts(with: searchQuery.lowercased()) {
                vcDelegate.focusEditArea()
            }

            searchTimer.invalidate()
            return true
        case "insertTab:":
            vcDelegate.focusEditArea()
            vcDelegate.editArea.scrollToCursor()
            return true
        case "deleteWordBackward:":
            textView.deleteWordBackward(self)
            return true
        case "noop:":
            if let event = NSApp.currentEvent, event.modifierFlags.contains(.command), event.keyCode == kVK_Return {
                vcDelegate.makeNote(self)
                return true
            }
            return false
        default:
            return false
        }
    }

    public func hasFocus() -> Bool {
        var inFocus = false
        inFocus = (window?.firstResponder is NSTextView) && window?.fieldEditor(false, for: nil) != nil && isEqual(to: (window?.firstResponder as? NSTextView)?.delegate)
        return inFocus
    }

    func controlTextDidChange(_ obj: Notification) {
        if UserDefaultsManagement.magicPPT {
            return
        }

        searchTimer.invalidate()

        if stringValue.isEmpty {
            vcDelegate.cleanSearchAndRestoreSelection()
        } else {
            searchTimer = Timer.scheduledTimer(timeInterval: 0.3, target: self, selector: #selector(search), userInfo: nil, repeats: false)
        }
    }

    public func suggestAutocomplete(_ note: Note, filter: String) {
        guard validateInput(note: note, filter: filter),
            let editor = currentEditor() as? NSTextView
        else { return }

        if note.title.lowercased().starts(with: filter.lowercased()) {
            applyAutocomplete(note: note, filter: filter, editor: editor)
        }
    }

    private func validateInput(note: Note, filter: String) -> Bool {
        return note.title != filter.lowercased() && !filter.isEmpty
    }

    private func applyAutocomplete(note: Note, filter: String, editor: NSTextView) {
        let suffix = note.title.suffix(note.title.count - filter.count)
        stringValue = filter + suffix
        editor.selectedRange = NSRange(filter.utf16.count..<note.title.utf16.count)
    }

    @objc private func search() {
        let text = stringValue

        guard !text.isEmpty else {
            vcDelegate.cleanSearchAndRestoreSelection()
            return
        }

        performSearch(with: text)
        updatePasteboard(with: text)
    }

    private func performSearch(with text: String) {
        UserDataService.instance.searchTrigger = true
        lastQueryLength = text.count

        filterQueue.cancelAllOperations()
        weak var delegate = vcDelegate
        filterQueue.addOperation { [weak delegate] in
            guard let delegate else { return }
            Task { @MainActor [weak delegate] in
                guard let delegate else { return }

                let projects = delegate.storageOutlineView.getSidebarProjects()
                let sidebarItem = projects == nil ? delegate.getSidebarItem() : nil

                delegate.updateTable(
                    search: true,
                    searchText: text,
                    sidebarItem: sidebarItem,
                    projects: projects
                ) {}
            }
        }
    }

    private func updatePasteboard(with text: String) {
        let pb = NSPasteboard(name: NSPasteboard.Name.find)
        pb.declareTypes([.textFinderOptions, .string], owner: nil)
        pb.setString(text, forType: NSPasteboard.PasteboardType.string)
    }
}
