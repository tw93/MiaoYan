import Carbon
import Cocoa

@MainActor
class NotesTableView: NSTableView {
    @MainActor
    private final class Adapter: NSObject, @preconcurrency NSTableViewDataSource, NSTableViewDelegate {
        unowned let owner: NotesTableView

        init(owner: NotesTableView) {
            self.owner = owner
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            owner.makeRowView(for: row)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            owner.noteList.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            owner.heightForRow(row)
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            owner.handleSelectionChange(notification)
        }

        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
            owner.objectValue(forRow: row)
        }

        func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
            owner.writeRows(rowIndexes: rowIndexes, to: pboard)
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            owner.viewForRow(row)
        }
    }

    private lazy var adapter = Adapter(owner: self)
    var noteList = [Note]()
    var defaultCell = NoteCellView()
    var pinnedCell = NoteCellView()
    var storage = Storage.sharedInstance()

    public var loadingQueue = OperationQueue()
    public var fillTimestamp: Int64?
    private var scrollSaveWorkItem: DispatchWorkItem?
    private var separatorSelectionRows: IndexSet?

    override func draw(_ dirtyRect: NSRect) {
        dataSource = adapter
        delegate = adapter
        backgroundColor = Theme.paneBackgroundColor
        super.draw(dirtyRect)
    }

    override func tile() {
        super.tile()
        guard let clipView = superview as? NSClipView,
            let column = tableColumns.first
        else { return }
        let clipWidth = clipView.bounds.width
        if abs(frame.width - clipWidth) > 0.5 {
            setFrameSize(NSSize(width: clipWidth, height: frame.height))
        }
        // Keep the title column narrower than the clip so long note names
        // truncate with a right-side gutter instead of butting against the
        // pane edge. The row separator and selection highlight still span the
        // full row width (they use the row bounds, not the column).
        let contentRightInset = Theme.Metrics.noteListContentInset
        let availableWidth = max(0, clipWidth - intercellSpacing.width - contentRightInset)
        if availableWidth > 0 {
            column.maxWidth = max(column.maxWidth, availableWidth)
        }
        if abs(column.width - availableWidth) > 0.5 && availableWidth > 0 {
            column.width = availableWidth
        }
        resetHorizontalScroll(in: clipView)
    }

    override func selectRowIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
        beginSynchronizedSelectionRedraw()
        defer { endSynchronizedSelectionRedraw() }

        let previousRows = currentSeparatorSelectionRows()
        let pendingRows = extend ? previousRows.union(indexes) : indexes

        separatorSelectionRows = pendingRows
        invalidateSeparatorRows(changingFrom: previousRows, to: pendingRows, flush: true)

        super.selectRowIndexes(indexes, byExtendingSelection: extend)

        syncSeparatorSelectionRows(previousRows: previousRows.union(pendingRows))
    }

    override func deselectRow(_ row: Int) {
        beginSynchronizedSelectionRedraw()
        defer { endSynchronizedSelectionRedraw() }

        let previousRows = currentSeparatorSelectionRows()
        var pendingRows = previousRows
        pendingRows.remove(row)

        separatorSelectionRows = pendingRows
        invalidateSeparatorRows(changingFrom: previousRows, to: pendingRows, flush: true)

        super.deselectRow(row)

        syncSeparatorSelectionRows(previousRows: previousRows.union(IndexSet(integer: row)))
    }

    override func deselectAll(_ sender: Any?) {
        beginSynchronizedSelectionRedraw()
        defer { endSynchronizedSelectionRedraw() }

        let previousRows = currentSeparatorSelectionRows()

        separatorSelectionRows = IndexSet()
        invalidateSeparatorRows(changingFrom: previousRows, to: IndexSet(), flush: true)

        super.deselectAll(sender)

        syncSeparatorSelectionRows(previousRows: previousRows)
    }

    func shouldHideNoteSeparator(for rowView: NoteRowView) -> Bool {
        let row = self.row(for: rowView)
        guard row >= 0 else { return false }

        let selectedRows = currentSeparatorSelectionRows()
        guard !selectedRows.isEmpty else { return false }

        return selectedRows.contains(row - 1) || selectedRows.contains(row + 1)
    }

    private func currentSeparatorSelectionRows() -> IndexSet {
        separatorSelectionRows ?? selectedRowIndexes
    }

    private func syncSeparatorSelectionRows(previousRows: IndexSet) {
        let currentRows = selectedRowIndexes
        separatorSelectionRows = currentRows
        invalidateSeparatorRows(changingFrom: previousRows, to: currentRows, flush: true)
    }

    private func beginSynchronizedSelectionRedraw() {
        window?.disableScreenUpdatesUntilFlush()
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
    }

    private func endSynchronizedSelectionRedraw() {
        displayIfNeeded()
        NSAnimationContext.endGrouping()
    }

    private func invalidateSeparatorRows(changingFrom previousRows: IndexSet, to currentRows: IndexSet, flush: Bool = false) {
        var changedRows = previousRows
        changedRows.formUnion(currentRows)

        var affectedRows = IndexSet()
        for row in changedRows {
            affectedRows.formUnion(separatorAffectedRows(around: row))
        }

        guard !affectedRows.isEmpty else { return }

        for row in affectedRows where row >= 0 && row < numberOfRows {
            if let rowView = rowView(atRow: row, makeIfNecessary: false) {
                rowView.needsDisplay = true
            } else {
                setNeedsDisplay(rect(ofRow: row))
            }
        }

        if flush {
            displayIfNeeded()
        }
    }

    private func separatorAffectedRows(around selectedRow: Int) -> IndexSet {
        guard selectedRow >= 0 else { return [] }

        var rows = IndexSet()
        for row in (selectedRow - 1)...(selectedRow + 1) where row >= 0 && row < numberOfRows {
            rows.insert(row)
        }
        return rows
    }

    override func keyUp(with event: NSEvent) {
        guard let vc = window?.contentViewController as? ViewController else {
            super.keyUp(with: event)
            return
        }

        let shouldUseEditorTextContent = vc.shouldUseEditorTextContent

        if EditTextView.note != nil, event.keyCode == kVK_Tab, !event.modifierFlags.contains(.control), shouldUseEditorTextContent {
            vc.focusEditArea()
            vc.editArea.updateTextContainerInset()
        }

        if event.keyCode == kVK_LeftArrow, !vc.sessionMagicPPTMode {
            if let fr = window?.firstResponder, fr.isKind(of: NSTextView.self) {
                super.keyUp(with: event)
                return
            }

            vc.storageOutlineView.window?.makeFirstResponder(vc.storageOutlineView)
            let index = vc.storageOutlineView.selectedRow
            vc.storageOutlineView.selectRowIndexes([index], byExtendingSelection: false)
            deselectNotes()
        }

        if event.keyCode == kVK_RightArrow, !vc.sessionMagicPPTMode {
            if let fr = window?.firstResponder, fr.isKind(of: NSTextView.self) {
                super.keyUp(with: event)
                return
            }

            if selectedRow == -1 && !noteList.isEmpty {
                selectRowIndexes([0], byExtendingSelection: false)
            }

            if EditTextView.note != nil {
                vc.focusEditArea()
                vc.editArea.updateTextContainerInset()
            }
        }

        if event.keyCode == kVK_Escape {
            if let fr = window?.firstResponder, fr === self {
                vc.storageOutlineView.window?.makeFirstResponder(vc.storageOutlineView)
                let index = vc.storageOutlineView.selectedRow
                vc.storageOutlineView.selectRowIndexes([index], byExtendingSelection: false)
                deselectNotes()
            }
        }

        super.keyUp(with: event)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        true
    }

    func scrollRowToVisible(row: Int, animated: Bool) {
        guard animated else {
            scrollRowToVisible(row)
            return
        }

        guard let clipView = superview as? NSClipView,
            let scrollView = clipView.superview as? NSScrollView
        else {
            assertionFailure("Unexpected NSTableView view hiearchy")
            return
        }

        let visibleRect = clipView.documentVisibleRect
        let rowRect = rect(ofRow: row)

        // Already fully visible – do nothing
        if visibleRect.contains(rowRect) {
            return
        }

        var targetRect = rowRect

        if rowRect.minY < visibleRect.minY {
            targetRect.origin.y = rowRect.minY
        } else {
            targetRect.origin.y = rowRect.maxY - visibleRect.height + 8.0
        }
        targetRect.origin.x = 0

        clipView.animator().setBoundsOrigin(targetRect.origin)
        if scrollView.responds(to: #selector(NSScrollView.flashScrollers)) {
            scrollView.flashScrollers()
        }
    }

    func isRowFullyVisible(_ row: Int) -> Bool {
        guard let clipView = superview as? NSClipView else { return true }
        let visibleRect = clipView.documentVisibleRect
        let rowRect = rect(ofRow: row)
        return visibleRect.contains(rowRect)
    }

    func currentScrollOrigin() -> NSPoint? {
        guard let clipView = superview as? NSClipView else { return nil }
        return clipView.bounds.origin
    }

    func restoreScrollOrigin(_ origin: NSPoint) {
        guard let clipView = superview as? NSClipView else { return }
        clipView.setBoundsOrigin(NSPoint(x: 0, y: origin.y))
    }

    override func mouseDown(with event: NSEvent) {
        UserDataService.instance.searchTrigger = false
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let vc = window?.contentViewController as? ViewController else { return }

        if vc.titleLabel.hasFocus() || vc.editArea.hasFocus() || vc.search.hasFocus() {
            vc.notesTableView.window?.makeFirstResponder(vc.notesTableView)
        }

        UserDataService.instance.searchTrigger = false

        let point = convert(event.locationInWindow, from: nil)
        let i = row(at: point)

        if noteList.indices.contains(i) {
            if !selectedRowIndexes.contains(i) {
                selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
                scrollRowToVisible(i)
            }
            super.rightMouseDown(with: event)
        }
    }

    private func makeRowView(for row: Int) -> NSTableRowView? {
        NoteRowView()
    }

    private func heightForRow(_ row: Int) -> CGFloat {
        if row < noteList.count {
            let note = noteList[row]
            note.dealContent()
        }
        return CGFloat(52)
    }

    private func handleSelectionChange(_ notification: Notification) {
        let timestamp = Date().toMillis()
        fillTimestamp = timestamp

        guard let vc = window?.contentViewController as? ViewController else { return }

        // Block note switching during an export. The PDF/PNG/HTML export
        // pipelines capture the live preview's outerHTML and snapshot
        // dimensions; if the user switches notes mid-export, the output's
        // filename comes from one note and the body from another. Toast
        // and re-select the previous row so the user gets explicit
        // feedback instead of a silently-mislabeled file.
        if vc.sessionIsExporting || vc.sessionIsExportingPPT || vc.sessionIsExportingHTML {
            if let currentNote = EditTextView.note,
                let row = self.getIndex(currentNote),
                row != self.selectedRow
            {
                self.selectRowIndexes([row], byExtendingSelection: false)
            }
            vc.toast(message: I18n.str("Switching notes is disabled during export~"), style: .failure)
            return
        }

        if let pendingChange = UserDataService.instance.pendingTitleChange {
            let title = pendingChange.title
            let note = pendingChange.note
            if !title.isEmpty && note.getFileName() != title {
                vc.saveTitle(title, to: note)
            }
            UserDataService.instance.pendingTitleChange = nil
        }

        if vc.editArea.isSearchBarVisible {
            vc.editArea.hideSearchBar(restoreFocus: false)
        }
        vc.editArea.markdownView?.hideSearchBar()

        if UserDataService.instance.isNotesTableEscape {
            UserDataService.instance.isNotesTableEscape = false

            if vc.storageOutlineView.selectedRow != -1 {
                vc.storageOutlineView.deselectAll(nil)
            }

            vc.editArea.clear()
            return
        }

        if noteList.indices.contains(selectedRow) {
            let note = noteList[selectedRow]
            if let currentNote = EditTextView.note, currentNote != note, vc.shouldUseEditorTextContent {
                // Tripwire: after the fill() epoch fix, EditTextView.note and
                // textStorage are in sync. The guard catches any future regression
                // before it writes the wrong bytes into the outgoing note's file.
                if EditTextView.note?.isEqualURL(url: currentNote.url) == true {
                    vc.editArea.saveTextStorageContent(to: currentNote)
                    currentNote.save(content: currentNote.content)
                } else {
                    let mismatch = NSError(
                        domain: "com.tw93.miaoyan.race",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "EditTextView.note URL drift in tableViewSelectionDidChange"])
                    AppDelegate.trackError(mismatch, context: "NotesTableView.tableViewSelectionDidChange.urlGuard")
                }
            }

            if !suppressSelectionSideEffects {
                saveScrollPosition()
            }

            if !UserDataService.instance.shouldBlockEditAreaUpdate() {
                vc.editArea.fill(note: note, options: .silent)
            }
        } else {
            // UX: Auto-select first note to avoid empty editor (unified behavior).
            // suppressSelectionSideEffects guards the brief window between
            // removeAndReselect's removeByNotes and its explicit
            // selectRowIndexes(target). Without this guard the auto-select
            // fallback would race the deterministic target selection through
            // ensureNoteSelection -> selectRow(0) on a DispatchQueue.main.async,
            // producing a row-0 flash for one frame before the right row lands.
            guard !suppressSelectionSideEffects else { return }
            if !noteList.isEmpty {
                vc.ensureNoteSelection()
            } else {
                vc.editArea.clear()
            }
        }
    }

    private func objectValue(forRow row: Int) -> Any? {
        if noteList.indices.contains(row) {
            return noteList[row]
        }
        return nil
    }

    private func writeRows(rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: rowIndexes, requiringSecureCoding: false) {
            let type = NSPasteboard.PasteboardType(rawValue: "notesTable")
            pboard.declareTypes([type], owner: self)
            pboard.setData(data, forType: type)
        }

        return true
    }

    private func selectedRowSafe() -> Int {
        if Thread.isMainThread { return selectedRow }
        var value = -1
        DispatchQueue.main.sync { value = self.selectedRow }
        return value
    }

    private func selectedRowIndexesSafe() -> IndexSet {
        if Thread.isMainThread { return selectedRowIndexes }
        var value = IndexSet()
        DispatchQueue.main.sync { value = self.selectedRowIndexes }
        return value
    }

    func getNoteFromSelectedRow() -> Note? {
        var note: Note?
        let selected = selectedRowSafe()

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
        let row = selectedRowSafe()
        if noteList.indices.contains(row) {
            note = noteList[row]
        }
        return note
    }

    func getSelectedNotes() -> [Note]? {
        var notes = [Note]()

        let rows = selectedRowIndexesSafe()
        for row in rows where noteList.indices.contains(row) {
            notes.append(noteList[row])
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
        if [kVK_ANSI_8].contains(Int(event.keyCode)), event.modifierFlags.contains(.command) {
            return true
        }

        if event.modifierFlags.contains(.control), event.keyCode == kVK_Tab {
            return true
        }

        if event.keyCode == kVK_ANSI_M, event.modifierFlags.contains(.command), event.modifierFlags.contains(.shift) {
            return true
        }

        return false
    }

    private func viewForRow(_ row: Int) -> NSView? {
        guard noteList.indices.contains(row) else {
            return nil
        }

        let note = noteList[row]
        if note.isPinned {
            pinnedCell = makeCell(note: note)
            return pinnedCell
        }

        defaultCell = makeCell(note: note)
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

        guard let vc = window?.contentViewController as? ViewController else {
            return
        }
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

    private var suppressSelectionSideEffects = false

    func selectRow(_ i: Int, ensureVisible: Bool = true, suppressSideEffects: Bool = false) {
        guard noteList.indices.contains(i) else { return }
        DispatchQueue.main.async {
            let previousSuppression = self.suppressSelectionSideEffects
            if suppressSideEffects {
                self.suppressSelectionSideEffects = true
            }
            self.selectRowIndexes([i], byExtendingSelection: false)
            if suppressSideEffects {
                self.suppressSelectionSideEffects = previousSuppression
            }
            guard ensureVisible else { return }
            if !self.isRowFullyVisible(i) {
                self.scrollRowToVisible(i)
            }
        }
    }

    func setSelected(note: Note, ensureVisible: Bool = true, suppressSideEffects: Bool = false) {
        if let i = getIndex(note) {
            selectRow(i, ensureVisible: ensureVisible, suppressSideEffects: suppressSideEffects)
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

    /// Atomic delete-and-reselect for the active row(s).
    /// Without this helper, `removeByNotes` triggers a tableViewSelectionDidChange
    /// with selectedRow = -1, which the else-branch of handleSelectionChange
    /// turns into a synchronous `ensureNoteSelection()` -> auto-select row 0,
    /// then the caller's own `selectRow(originalRow)` jumps a second time.
    /// Two highlight flashes in two frames.
    ///
    /// We compute the deterministic next row before the removal, suppress the
    /// auto-select-first side effect for the duration of removeRows, and then
    /// commit the next row in the same synchronous stretch.
    func removeAndReselect(notes: [Note], originalRow: Int) {
        let removedAbove = noteList.prefix(max(originalRow, 0))
            .filter { n in notes.contains(where: { $0 === n }) }
            .count
        let prospective = max(originalRow - removedAbove, 0)

        // Keep suppression on for the whole sequence: removeByNotes synchronously
        // fires selectionDidChange with selectedRow=-1 between the row removal
        // and our explicit reselection below. Without this, the else branch of
        // handleSelectionChange would call ensureNoteSelection -> selectRow(0)
        // (async via DispatchQueue.main.async), producing a row-0 highlight
        // flash one frame before the deterministic target lands.
        let previousSuppression = suppressSelectionSideEffects
        suppressSelectionSideEffects = true
        defer { suppressSelectionSideEffects = previousSuppression }

        removeByNotes(notes: notes)

        guard !noteList.isEmpty else {
            return
        }

        let target = min(prospective, noteList.count - 1)
        if selectedRow != target {
            // Briefly drop suppression so the selectRowIndexes-driven
            // selectionDidChange runs the IF branch's fill(note:.silent),
            // which is exactly the editor refresh we want for the new row.
            suppressSelectionSideEffects = previousSuppression
            selectRowIndexes([target], byExtendingSelection: false)
            suppressSelectionSideEffects = true
            if !isRowFullyVisible(target) {
                scrollRowToVisible(target)
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
                AppDelegate.trackError(error, context: "NotesTableView.reloadRow")
            }
        }
    }

    public func countVisiblePinned() -> Int {
        var i = 0
        for note in noteList where note.isPinned {
            i += 1
        }
        return i
    }

    public func insertNew(note: Note) {
        guard let vc = window?.contentViewController as? ViewController else {
            return
        }

        let at = countVisiblePinned()
        noteList.insert(note, at: at)
        vc.filteredNoteList?.insert(note, at: at)

        beginUpdates()
        insertRows(at: IndexSet(integer: at), withAnimation: .effectFade)
        reloadData(forRowIndexes: IndexSet(integer: at), columnIndexes: [0])
        endUpdates()
    }

    override func keyDown(with event: NSEvent) {
        let vc = window?.contentViewController as? ViewController
        if vc?.sessionMagicPPTMode == true {
            return
        }
        if event.modifierFlags.contains(.control),
            !event.modifierFlags.contains(.option), event.modifierFlags.contains(.shift), event.keyCode == kVK_ANSI_P
        {
            vc?.exportPdf(self)
            return
        }

        if event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option), event.modifierFlags.contains(.shift), event.keyCode == kVK_ANSI_I {
            vc?.exportImage(self)
            return
        }

        if event.modifierFlags.contains(.option), event.modifierFlags.contains(.control), event.modifierFlags.contains(.shift), event.keyCode == kVK_ANSI_P {
            vc?.exportMiaoYanPPT(self)
            return
        }

        if let vc = window?.contentViewController as? ViewController {
            if !vc.handleKeyDown(with: event) {
                super.keyDown(with: event)
            }
        } else {
            super.keyDown(with: event)
        }
    }

    public func reloadRow(note: Note) {
        let storedTitle = note.title

        note.invalidateCache()
        if note.title.isEmpty && !storedTitle.isEmpty {
            note.title = storedTitle
        }

        guard let row = noteList.firstIndex(where: { $0 === note }) else {
            reloadData()
            return
        }

        reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
    }

    // MARK: - Scroll Position Memory
    func saveScrollPosition() {
        guard let clipView = superview as? NSClipView else { return }

        // Cancel previous pending save
        scrollSaveWorkItem?.cancel()

        let scrollPosition = clipView.bounds.origin.y
        let contextURL = currentScrollContextURL()

        let workItem = DispatchWorkItem {
            UserDefaultsManagement.setNotesTableScrollPosition(scrollPosition, for: contextURL)
        }

        scrollSaveWorkItem = workItem
        // Debounce for 0.8 seconds to avoid frequent writes during rapid scrolling
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    @discardableResult
    func restoreScrollPosition(ensureSelectionVisible: Bool = true) -> Bool {
        let contextURL = currentScrollContextURL()
        let savedPosition = UserDefaultsManagement.notesTableScrollPosition(for: contextURL)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let newOrigin = NSPoint(x: 0, y: savedPosition)
            self.restoreScrollOrigin(newOrigin)
            guard ensureSelectionVisible else { return }
            let selectedRow = self.selectedRowSafe()
            if selectedRow >= 0, !self.isRowFullyVisible(selectedRow) {
                self.scrollRowToVisible(row: selectedRow, animated: false)
            }
        }
        return savedPosition > 0
    }

    private func resetHorizontalScroll(in clipView: NSClipView) {
        guard clipView.bounds.origin.x != 0 else { return }
        clipView.scroll(to: NSPoint(x: 0, y: clipView.bounds.origin.y))
        (clipView.superview as? NSScrollView)?.reflectScrolledClipView(clipView)
    }

    private func currentScrollContextURL() -> URL? {
        if let vc = window?.contentViewController as? ViewController,
            let sidebar = vc.storageOutlineView
        {
            let selectedRow = sidebar.selectedRow
            if selectedRow >= 0,
                let item = sidebar.item(atRow: selectedRow) as? SidebarItem
            {
                if let project = item.project {
                    return project.url
                }
                if item.type == .All {
                    return nil
                }
            }
        }

        if let selectedNote = getSelectedNote() {
            return selectedNote.project.url
        }

        return UserDataService.instance.lastProject
    }
}
