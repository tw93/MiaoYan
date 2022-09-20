import Carbon.HIToolbox
import Cocoa

import MiaoYanCore_macOS

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

    override func updateTrackingAreas() {
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }

    override var cancelButtonBounds: NSRect {
        NSZeroRect
    }

    override func textDidEndEditing(_ notification: Notification) {
        if let editor = currentEditor(), editor.selectedRange.length > 0 {
            editor.replaceCharacters(in: editor.selectedRange, with: "")
            window?.makeFirstResponder(nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let vc = window?.contentViewController as! ViewController
        vc.titleLabel.saveTitle()
        super.mouseDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == kVK_DownArrow {
            vcDelegate.focusTable()
            vcDelegate.notesTableView.selectNext()
            return
        }

        if event.keyCode == kVK_LeftArrow && stringValue.count == 0 {
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
                if query.count == 0 {
                    return false
                }
                stringValue = String(query)
            }
            return true
        case "cancelOperation:":
            return true
        case "deleteBackward:":
            skipAutocomplete = true
            textView.deleteBackward(self)
            return true
        case "insertNewline:", "insertNewlineIgnoringFieldEditor:":
            if let note = vcDelegate.editArea.getSelectedNote(), stringValue.count > 0, note.title.lowercased().starts(with: searchQuery.lowercased()) {
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
        searchTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(search), userInfo: nil, repeats: false)
    }

    public func suggestAutocomplete(_ note: Note, filter: String) {
        guard note.title != filter.lowercased(), let editor = currentEditor() else { return }

        if note.title.lowercased().starts(with: filter.lowercased()) {
            stringValue = filter + note.title.suffix(note.title.count - filter.count)
            editor.selectedRange = NSRange(filter.utf16.count ..< note.title.utf16.count)
        }
    }

    @objc private func search() {
        UserDataService.instance.searchTrigger = true

        let searchText = stringValue
        var sidebarItem: SidebarItem?

        lastQueryLength = searchText.count

        let projects = vcDelegate.storageOutlineView.getSidebarProjects()

        if projects == nil {
            sidebarItem = vcDelegate.getSidebarItem()
        }

        filterQueue.cancelAllOperations()
        filterQueue.addOperation {
            self.vcDelegate.updateTable(search: true, searchText: searchText, sidebarItem: sidebarItem, projects: projects) {}
        }

        let pb = NSPasteboard(name: NSPasteboard.Name.find)
        pb.declareTypes([.textFinderOptions, .string], owner: nil)
        pb.setString(searchText, forType: NSPasteboard.PasteboardType.string)
    }
}
