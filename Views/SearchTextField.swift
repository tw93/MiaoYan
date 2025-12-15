import Carbon.HIToolbox
import Cocoa

class SearchFieldCell: NSSearchFieldCell {
    static let height: CGFloat = 30
    private static let padding: CGFloat = 12
    private static let lineHeight: CGFloat = 17.0

    override var cellSize: NSSize {
        var size = super.cellSize
        size.height = Self.height
        return size
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let insetFrame = cellFrame.insetBy(dx: 0.5, dy: 0.5)
        drawBackground(in: insetFrame)
        drawBorder(in: insetFrame, appearance: controlView.effectiveAppearance)
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    private func drawBackground(in frame: NSRect) {
        let path = NSBezierPath(roundedRect: frame, xRadius: Self.height / 2, yRadius: Self.height / 2)
        (NSColor(named: "mainBackground") ?? NSColor.controlBackgroundColor).setFill()
        path.fill()
    }

    private func drawBorder(in frame: NSRect, appearance: NSAppearance?) {
        let path = NSBezierPath(roundedRect: frame, xRadius: Self.height / 2, yRadius: Self.height / 2)
        Theme.dividerColor.resolvedColor(for: appearance).setStroke()
        path.lineWidth = 1.0
        path.stroke()
    }

    override func searchTextRect(forBounds rect: NSRect) -> NSRect {
        return NSRect(
            x: rect.origin.x + Self.padding,
            y: rect.origin.y + (rect.height - Self.lineHeight) / 2,
            width: rect.width - Self.padding * 2,
            height: Self.lineHeight
        )
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        // Same as searchTextRect for placeholder
        return searchTextRect(forBounds: rect)
    }
}

class SearchTextField: NSSearchField, NSSearchFieldDelegate {
    public var vcDelegate: ViewController!

    private var filterQueue = OperationQueue()
    private var searchTimer = Timer()

    public var searchQuery = ""
    public var selectedRange = NSRange()
    public var skipAutocomplete = false

    public var timestamp: Int64?
    private var lastQueryLength: Int = 0

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.height = SearchFieldCell.height
        return size
    }

    override func setFrameSize(_ newSize: NSSize) {
        var adjustedSize = newSize
        adjustedSize.height = SearchFieldCell.height
        super.setFrameSize(adjustedSize)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            configureSearchField()
        }
    }

    @MainActor private func configureSearchField() {
        if let searchFieldCell = self.cell as? NSSearchFieldCell {
            searchFieldCell.searchButtonCell = nil
            searchFieldCell.cancelButtonCell = nil
            searchFieldCell.placeholderString = I18n.str("Search")
        }

        sendsWholeSearchString = false
        sendsSearchStringImmediately = true
        invalidateIntrinsicContentSize()
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
            guard let editor = currentEditor() else {
                return false
            }
            let query = editor.string.prefix(editor.selectedRange.location)
            guard !query.isEmpty else {
                return false
            }
            stringValue = String(query)
            return true
        case "cancelOperation:":
            stringValue = ""
            vcDelegate.cleanSearchAndRestoreSelection()
            return true
        case "deleteBackward:":
            skipAutocomplete = true
            textView.deleteBackward(self)
            return true
        case "deleteToBeginningOfLine:", "deleteToBeginningOfParagraph:":
            textView.selectAll(nil)
            textView.delete(nil)
            stringValue = ""
            vcDelegate.cleanSearchAndRestoreSelection()
            return true
        case "insertNewline:", "insertNewlineIgnoringFieldEditor:":
            if let note = vcDelegate.editArea.getSelectedNote(),
                !stringValue.isEmpty,
                note.title.lowercased().starts(with: searchQuery.lowercased())
            {
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
            if let event = NSApp.currentEvent,
                event.modifierFlags.contains(.command),
                event.keyCode == kVK_Return
            {
                vcDelegate.makeNote(self)
                return true
            }
            return false
        default:
            return false
        }
    }

    public func hasFocus() -> Bool {
        guard let window = window,
            let firstResponder = window.firstResponder as? NSTextView,
            window.fieldEditor(false, for: nil) != nil,
            isEqual(to: firstResponder.delegate)
        else {
            return false
        }
        return true
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
        guard note.title != filter.lowercased(),
            !filter.isEmpty,
            let editor = currentEditor() as? NSTextView,
            note.title.lowercased().starts(with: filter.lowercased())
        else { return }

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
        filterQueue.addOperation { [weak delegate = vcDelegate] in
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
