import Carbon
import Cocoa
import MiaoYanCore_macOS

class NotesTableView: NSTableView, NSTableViewDataSource,
    NSTableViewDelegate
{
    var noteList = [Note]()
    var defaultCell = NoteCellView()
    var pinnedCell = NoteCellView()
    var storage = Storage.sharedInstance()

    public var loadingQueue = OperationQueue()
    public var fillTimestamp: Int64?

    override func draw(_ dirtyRect: NSRect) {
        dataSource = self
        delegate = self
        if UserDefaultsManagement.appearanceType != AppearanceType.Custom, #available(OSX 10.13, *) {
            NSColor(named: "mainBackground")!.setFill()
            __NSRectFill(dirtyRect)
        } else {
            layer?.backgroundColor = NSColor.white.cgColor
        }
        super.draw(dirtyRect)
    }

    override func keyUp(with event: NSEvent) {
        guard let vc = window?.contentViewController as? ViewController else {
            super.keyUp(with: event)
            return
        }

        if let _ = EditTextView.note, event.keyCode == kVK_Tab, !event.modifierFlags.contains(.control), !UserDefaultsManagement.preview {
            vc.focusEditArea()
            vc.editArea.updateTextContainerInset()
        }

        if event.keyCode == kVK_LeftArrow {
            if let fr = window?.firstResponder, fr.isKind(of: NSTextView.self) {
                super.keyUp(with: event)
                return
            }

            vc.storageOutlineView.window?.makeFirstResponder(vc.storageOutlineView)
            vc.storageOutlineView.selectRowIndexes([1], byExtendingSelection: false)
        }

        super.keyUp(with: event)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        UserDataService.instance.searchTrigger = false
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        UserDataService.instance.searchTrigger = false

        let point = convert(event.locationInWindow, from: nil)
        let i = row(at: point)

        if noteList.indices.contains(i) {
            DispatchQueue.main.async {
                let selectedRows = self.selectedRowIndexes
                if !selectedRows.contains(i) {
                    self.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
                    self.scrollRowToVisible(i)
                    return
                }
            }

            super.rightMouseDown(with: event)
        }
    }

    // Custom note highlight style
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return NoteRowView()
    }

    // Populate table data
    func numberOfRows(in tableView: NSTableView) -> Int {
        return noteList.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if row < noteList.count {
            let note = noteList[row]
            note.dealContent()
        }

        return CGFloat(52)
    }

    // On selected row show notes in right panel
    func tableViewSelectionDidChange(_ notification: Notification) {
        let timestamp = Date().toMillis()
        fillTimestamp = timestamp

        let vc = window?.contentViewController as! ViewController

        if vc.editAreaScroll.isFindBarVisible {
            let menu = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            menu.tag = NSTextFinder.Action.hideFindInterface.rawValue
            vc.editArea.performTextFinderAction(menu)
        }

        if UserDataService.instance.isNotesTableEscape {
            if vc.storageOutlineView.selectedRow == -1 {
                UserDataService.instance.isNotesTableEscape = false
            }

            vc.storageOutlineView.deselectAll(nil)

            vc.editArea.clear()
            return
        }

        if noteList.indices.contains(selectedRow) {
            let note = noteList[selectedRow]
            loadingQueue.cancelAllOperations()
            let operation = BlockOperation()
            operation.addExecutionBlock { [weak self] in
                DispatchQueue.main.async {
                    guard !operation.isCancelled, self?.fillTimestamp == timestamp else { return }

                    vc.editArea.fill(note: note, highlight: true)
                }
            }
            loadingQueue.addOperation(operation)
        } else {
            vc.editArea.clear()
        }
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if noteList.indices.contains(row) {
            return noteList[row]
        }
        return nil
    }

    func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
        let data = NSKeyedArchiver.archivedData(withRootObject: rowIndexes)
        let type = NSPasteboard.PasteboardType(rawValue: "notesTable")
        pboard.declareTypes([type], owner: self)
        pboard.setData(data, forType: type)
        return true
    }

    func getNoteFromSelectedRow() -> Note? {
        var note: Note?
        let selected = selectedRow

        if selected < 0 {
            return nil
        }

        if noteList.indices.contains(selected) {
            note = noteList[selected]
        }

        return note
    }

    func getSelectedNote() -> Note? {
        var note: Note?
        let row = selectedRow
        if noteList.indices.contains(row) {
            note = noteList[row]
        }
        return note
    }

    func getSelectedNotes() -> [Note]? {
        var notes = [Note]()

        for row in selectedRowIndexes {
            if noteList.indices.contains(row) {
                notes.append(noteList[row])
            }
        }

        if notes.isEmpty {
            return nil
        }

        return notes
    }

    public func deselectNotes() {
        deselectAll(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if [kVK_ANSI_8, kVK_ANSI_J, kVK_ANSI_K].contains(Int(event.keyCode)), event.modifierFlags.contains(.command) {
            return true
        }

        if event.modifierFlags.contains(.control), event.keyCode == kVK_Tab {
            return true
        }

        if event.keyCode == kVK_ANSI_M, event.modifierFlags.contains(.command), event.modifierFlags.contains(.shift) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard noteList.indices.contains(row) else {
            return nil
        }

        let note = noteList[row]
        if note.isPinned {
            pinnedCell = makeCell(note: note)
            pinnedCell.pin.frame.size.width = 23
            return pinnedCell
        }

        defaultCell = makeCell(note: note)
        defaultCell.pin.frame.size.width = 0
        return defaultCell
    }

    func makeCell(note: Note) -> NoteCellView {
        let cell = makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "NoteCellView"), owner: self) as! NoteCellView

        cell.configure(note: note)
        cell.attachHeaders(note: note)

        return cell
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        if clickedRow > -1, selectedRow < 0 {
            selectRowIndexes([clickedRow], byExtendingSelection: false)
        }

        if selectedRow < 0 {
            return
        }

        guard let vc = window?.contentViewController as? ViewController else { return }
        vc.loadMoveMenu()
    }

    func getIndex(_ note: Note) -> Int? {
        if let index = noteList.firstIndex(where: { $0 === note }) {
            return index
        }
        return nil
    }

    func selectNext() {
        UserDataService.instance.searchTrigger = false

        selectRow(selectedRow + 1)
    }

    func selectPrev() {
        UserDataService.instance.searchTrigger = false

        selectRow(selectedRow - 1)
    }

    func selectRow(_ i: Int) {
        if noteList.indices.contains(i) {
            DispatchQueue.main.async {
                self.selectRowIndexes([i], byExtendingSelection: false)
                self.scrollRowToVisible(i)
            }
        }
    }

    func setSelected(note: Note) {
        if let i = getIndex(note) {
            selectRow(i)
            scrollRowToVisible(i)
        }
    }

    func removeByNotes(notes: [Note]) {
        for note in notes {
            if let i = noteList.firstIndex(where: { $0 === note }) {
                let indexSet = IndexSet(integer: i)
                noteList.remove(at: i)
                removeRows(at: indexSet, withAnimation: .slideDown)
            }
        }
    }

    @objc public func unDelete(_ urls: [URL: URL]) {
        for (src, dst) in urls {
            do {
                if let note = storage.getBy(url: src) {
                    storage.removeBy(note: note)
                }

                try FileManager.default.moveItem(at: src, to: dst)
            } catch {
                print(error)
            }
        }
    }

    public func countVisiblePinned() -> Int {
        var i = 0
        for note in noteList {
            if note.isPinned {
                i += 1
            }
        }
        return i
    }

    public func insertNew(note: Note) {
        guard let vc = window?.contentViewController as? ViewController else { return }

        let at = countVisiblePinned()
        noteList.insert(note, at: at)
        vc.filteredNoteList?.insert(note, at: at)

        beginUpdates()
        insertRows(at: IndexSet(integer: at), withAnimation: .effectFade)
        reloadData(forRowIndexes: IndexSet(integer: at), columnIndexes: [0])
        endUpdates()
    }
    
    override func keyDown(with event: NSEvent) {
        let vc = window?.contentViewController as? ViewController;
        if event.modifierFlags.contains(.control), event.modifierFlags.contains(.shift), event.keyCode == kVK_ANSI_P {
            vc?.exportPdf("")
            return
        }

        if event.modifierFlags.contains(.control), event.modifierFlags.contains(.shift), event.keyCode == kVK_ANSI_I {
            vc?.exportImage("")
            return
        }

        super.keyDown(with: event)
    }

    public func reloadRow(note: Note) {
        note.invalidateCache()
        DispatchQueue.main.async {
            if let i = self.noteList.firstIndex(of: note) {
                if let row = self.rowView(atRow: i, makeIfNecessary: false) as? NoteRowView, let cell = row.subviews.first as? NoteCellView {
                    cell.date.stringValue = note.getDateForLabel()
                    cell.attachHeaders(note: note)
                    cell.renderPin()

                    self.noteHeightOfRows(withIndexesChanged: [i])
                }
            }
        }
    }
}
