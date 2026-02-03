import Cocoa

// MARK: - Search Parameters
private struct SearchParameters: Sendable {
    let filter: String
    let originalFilter: String
    let projects: [Project]?
    let type: SidebarItemType?
    let sidebarName: String?
}

private struct NoteSearchResult {
    let note: Note
    let priority: Int
    let modifiedAt: Date
}

private struct UpdateContext {
    let isSearch: Bool
    let searchParams: SearchParameters
    let operation: Operation
    let completion: () -> Void
}

private final class AsyncSearchOperation: Operation, @unchecked Sendable {
    var task: ((@escaping () -> Void) -> Void)?

    private let stateLock = NSLock()
    private var _isExecuting = false
    private var _isFinished = false

    override var isAsynchronous: Bool { true }

    override var isExecuting: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isExecuting
    }

    override var isFinished: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isFinished
    }

    override func start() {
        if isCancelled {
            finish()
            return
        }

        setExecuting(true)
        guard let task = task else {
            finish()
            return
        }
        task { [weak self] in
            self?.finish()
        }
    }

    private func setExecuting(_ executing: Bool) {
        willChangeValue(forKey: "isExecuting")
        stateLock.lock()
        _isExecuting = executing
        stateLock.unlock()
        didChangeValue(forKey: "isExecuting")
    }

    private func setFinished(_ finished: Bool) {
        willChangeValue(forKey: "isFinished")
        stateLock.lock()
        _isFinished = finished
        stateLock.unlock()
        didChangeValue(forKey: "isFinished")
    }

    private func finish() {
        if isFinished {
            return
        }
        setExecuting(false)
        setFinished(true)
    }
}

// MARK: - Data Management
extension ViewController {

    // MARK: - Search and Filtering
    func updateTable(search: Bool = false, searchText: String? = nil, sidebarItem: SidebarItem? = nil, projects: [Project]? = nil, completion: @escaping @MainActor @Sendable () -> Void = {}) {
        let searchParams = prepareSearchParameters(searchText: searchText, sidebarItem: sidebarItem, projects: projects)

        // Ensure notes are loaded for the selected project(s)
        if let projects = searchParams.projects {
            for project in projects {
                storage.loadMissingNotes(for: project)
            }
        }

        let timestamp = Date().toMillis()

        self.search.timestamp = timestamp
        searchQueue.cancelAllOperations()

        let operation = createSearchOperation(
            searchParams: searchParams,
            isSearch: search,
            completion: completion
        )

        searchQueue.addOperation(operation)
    }

    private func prepareSearchParameters(searchText: String?, sidebarItem: SidebarItem?, projects: [Project]?) -> SearchParameters {
        var finalSidebarItem = sidebarItem
        var finalProjects = projects
        var sidebarName: String?

        if searchText == nil,
            UserDefaultsManagement.isSingleMode,
            finalProjects == nil
        {
            let singleModeUrl = URL(fileURLWithPath: UserDefaultsManagement.singleModePath).resolvingSymlinksInPath()
            if let project = storage.getProjectBy(url: singleModeUrl) {
                finalProjects = [project]
            }
        }

        if searchText == nil {
            if finalProjects == nil {
                finalProjects = storageOutlineView.getSidebarProjects()
            }
            if finalSidebarItem == nil {
                finalSidebarItem = getSidebarItem()
            }
            sidebarName = finalSidebarItem?.getName()
        }

        let filter = searchText ?? self.search.stringValue
        let originalFilter = filter
        let lowercaseFilter = originalFilter.lowercased()

        var type = finalSidebarItem?.type

        // Global search if sidebar not checked
        if type == nil, finalProjects == nil || (finalProjects!.count < 2 && finalProjects!.first!.isRoot) {
            type = .All
        }

        return SearchParameters(
            filter: lowercaseFilter,
            originalFilter: originalFilter,
            projects: finalProjects,
            type: type,
            sidebarName: sidebarName
        )
    }

    private func createSearchOperation(searchParams: SearchParameters, isSearch: Bool, completion: @escaping @MainActor @Sendable () -> Void) -> Operation {
        let operation = AsyncSearchOperation()
        operation.task = { [weak self, weak operation] finish in
            guard let self = self else {
                Task { @MainActor in
                    completion()
                    finish()
                }
                return
            }

            Task { @MainActor [weak self, weak operation] in
                guard let self else {
                    completion()
                    finish()
                    return
                }

                guard let operation, !operation.isCancelled else {
                    completion()
                    finish()
                    return
                }

                self.executeSearchOperation(
                    searchParams: searchParams,
                    isSearch: isSearch,
                    operation: operation,
                    completion: {
                        completion()
                        finish()
                    }
                )
            }
        }
        return operation
    }

    private func executeSearchOperation(searchParams: SearchParameters, isSearch: Bool, operation: Operation, completion: @escaping () -> Void) {
        if let projects = searchParams.projects {
            for project in projects {
                preLoadNoteTitles(in: project)
            }
        }

        let notesWithPriority = filterNotes(
            searchParams: searchParams,
            isSearch: isSearch,
            operation: operation,
            completion: completion
        )

        guard !operation.isCancelled else {
            completion()
            return
        }

        // Sort by priority first, then by modification date
        let sortedNotes: [NoteSearchResult]
        if !searchParams.filter.isEmpty {
            sortedNotes = notesWithPriority.sorted { first, second in
                // Higher priority first
                if first.priority != second.priority {
                    return first.priority > second.priority
                }
                // Within same priority, sort by modification date
                return first.modifiedAt > second.modifiedAt
            }
        } else {
            sortedNotes = notesWithPriority
        }

        let notes = sortedNotes.map { $0.note }
        let orderedNotesList =
            searchParams.filter.isEmpty
            ? storage.sortNotes(
                noteList: notes,
                filter: searchParams.filter,
                project: searchParams.projects?.first,
                operation: operation
            )
            : notes

        updateTableViewWithResults(
            notes: notes,
            orderedNotesList: orderedNotesList,
            context: UpdateContext(
                isSearch: isSearch,
                searchParams: searchParams,
                operation: operation,
                completion: completion
            )
        )
    }

    private func filterNotes(searchParams: SearchParameters, isSearch: Bool, operation: Operation, completion: @escaping () -> Void) -> [NoteSearchResult] {
        let terms = searchParams.filter.split(separator: " ")
        let source = storage.noteList
        var notes: [NoteSearchResult] = []
        let maxResults = isSearch ? 100 : Int.max

        for note in source {
            if operation.isCancelled {
                completion()
                return []
            }

            if isFit(
                note: note,
                filter: searchParams.filter,
                terms: terms,
                projects: searchParams.projects,
                type: searchParams.type,
                sidebarName: searchParams.sidebarName
            ) {
                let matchResult = isMatched(note: note, terms: terms)
                if matchResult.matched {
                    notes.append(NoteSearchResult(note: note, priority: matchResult.priority, modifiedAt: note.modifiedLocalAt))

                    if isSearch && notes.count >= maxResults {
                        break
                    }
                }
            }
        }

        return notes
    }

    private func updateTableViewWithResults(notes: [Note], orderedNotesList: [Note], context: UpdateContext) {
        // Check if results have changed
        if filteredNoteList == notes, orderedNotesList == notesTableView.noteList {
            context.completion()
            return
        }

        let previouslySelectedNote = notesTableView.getSelectedNote()
        let previousSelectedRow = notesTableView.selectedRow
        let previousScrollOrigin = notesTableView.currentScrollOrigin()

        filteredNoteList = notes
        notesTableView.noteList = orderedNotesList

        guard !context.operation.isCancelled else {
            context.completion()
            return
        }

        if notesTableView.noteList.isEmpty {
            handleEmptyResults(completion: context.completion)
        } else {
            handleNonEmptyResults(
                isSearch: context.isSearch,
                searchParams: context.searchParams,
                previousSelection: previouslySelectedNote,
                previousSelectedRow: previousSelectedRow,
                previousScrollOrigin: previousScrollOrigin,
                completion: context.completion
            )
        }
    }

    private func handleEmptyResults(completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            if !UserDefaultsManagement.isSingleMode {
                self.editArea.clear()
            }
            self.notesTableView.reloadData()
            completion()
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func handleNonEmptyResults(
        isSearch: Bool,
        searchParams: SearchParameters,
        previousSelection: Note?,
        previousSelectedRow: Int,
        previousScrollOrigin: NSPoint?,
        completion: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            self.notesTableView.reloadData()

            if isSearch {
                self.handleSearchResults(searchParams: searchParams)
            }

            let didRestoreScroll: Bool
            if let origin = previousScrollOrigin {
                self.notesTableView.restoreScrollOrigin(origin)
                didRestoreScroll = true
            } else {
                didRestoreScroll = self.notesTableView.restoreScrollPosition(ensureSelectionVisible: false)
            }

            if !UserDefaultsManagement.isSingleMode {
                let selectionRestored = self.restoreSelectionIfNeeded(
                    previouslySelectedNote: previousSelection,
                    fallbackRow: previousSelectedRow,
                    preserveScrollPosition: didRestoreScroll
                )
                if !isSearch {
                    // If we already have a valid selection (e.g., restored during preview mode startup),
                    // don't override it. Only call ensureNoteSelection if no note is selected.
                    let hasValidSelection = self.notesTableView.selectedRow >= 0
                    if !hasValidSelection {
                        let shouldPreferLastSelection = self.storageOutlineView?.isLaunch ?? false
                        let shouldPreserveScroll = didRestoreScroll && !selectionRestored
                        self.ensureNoteSelection(
                            preferLastSelected: shouldPreferLastSelection,
                            preserveScrollPosition: shouldPreserveScroll
                        )
                    }
                }
            }

            // Fix: Deep Safeguard against missed selection updates
            // We delay the check slightly to allow for view layout and notification propagation.
            // This handles cases where the view is hidden on launch and suppresses selection notifications.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if UserDefaultsManagement.isSingleMode {
                    self.revealEditor()
                    return
                }
                if self.notesTableView.loadingQueue.operationCount == 0, EditTextView.note == nil {
                    // Case 1: Standard Selection Success
                    if let selectedNote = self.notesTableView.getSelectedNote() {
                        self.editArea.fill(note: selectedNote, options: .silent)
                        self.revealEditor()
                    }
                    // Case 2: Selection missed/racing but data exists
                    else if !self.notesTableView.noteList.isEmpty {
                        let firstNote = self.notesTableView.noteList[0]

                        // Force selection execution for UI consistency
                        self.notesTableView.selectRowIndexes([0], byExtendingSelection: false)
                        self.notesTableView.scrollRowToVisible(0)

                        self.editArea.fill(note: firstNote, options: .silent)
                        self.revealEditor()
                    } else {
                        // Reveal anyway if we have no notes (empty state)
                        self.revealEditor()
                    }
                } else {
                    // Ensure visible if already filled (e.g. by normal flow)
                    self.revealEditor()
                }
            }

            completion()
        }
    }

    private func handleSearchResults(searchParams: SearchParameters) {
        let hasSelectedNote = notesTableView.getSelectedNote() != nil

        if !notesTableView.noteList.isEmpty {
            if !searchParams.filter.isEmpty {
                selectNullTableRow(timer: true)
            } else if !UserDefaultsManagement.isSingleMode, !hasSelectedNote {
                editArea.clear()
            }
        } else if !UserDefaultsManagement.isSingleMode, !hasSelectedNote {
            editArea.clear()
        }
    }

    @discardableResult
    private func restoreSelectionIfNeeded(previouslySelectedNote: Note?, fallbackRow: Int, preserveScrollPosition: Bool) -> Bool {
        if let note = previouslySelectedNote,
            notesTableView.noteList.contains(where: { $0 === note })
        {
            notesTableView.setSelected(
                note: note,
                ensureVisible: !preserveScrollPosition,
                suppressSideEffects: true
            )
            return true
        }

        if fallbackRow != -1,
            notesTableView.noteList.indices.contains(fallbackRow)
        {
            notesTableView.selectRow(
                fallbackRow,
                suppressSideEffects: preserveScrollPosition
            )
            return true
        }

        return false
    }

    private func preLoadNoteTitles(in project: Project) {
        if UserDefaultsManagement.sort == .title || project.sortBy == .title {
            _ = storage.noteList.filter {
                $0.project == project
            }
        }
    }

    private func isMatched(note: Note, terms: [Substring]) -> (matched: Bool, priority: Int) {
        guard !terms.isEmpty else {
            return (true, 0)
        }

        // Pre-lowercase all search terms once to avoid repeated conversions
        let lowercaseTerms = terms.map { $0.lowercased() }
        let lowercaseTitle = note.name.lowercased()

        var titleMatchCount = 0

        // First pass: check title only (fast path)
        for term in lowercaseTerms where lowercaseTitle.contains(term) {
            titleMatchCount += 1
        }

        // If all terms match in title, highest priority - skip content search
        if titleMatchCount == terms.count {
            return (true, 4)
        }

        // Second pass: check content for unmatched terms
        note.ensureContentLoaded()
        let lowercaseContent = note.content.string.lowercased()
        var contentMatchCount = 0

        for term in lowercaseTerms {
            // Skip if already matched in title
            if lowercaseTitle.contains(term) {
                continue
            }
            // Check content
            if lowercaseContent.contains(term) {
                contentMatchCount += 1
            } else {
                // Term not found in either title or content
                return (false, 0)
            }
        }

        // Calculate priority based on match distribution
        // Priority: 4=all in title, 3=mostly title, 2=mixed, 1=mostly content
        let priority: Int
        if titleMatchCount > contentMatchCount {
            priority = 3
        } else if titleMatchCount > 0 {
            priority = 2
        } else {
            priority = 1
        }

        return (true, priority)
    }

    public func isFit(note: Note, filter: String = "", terms: [Substring]? = nil, shouldLoadMain: Bool = false, projects: [Project]? = nil, type: SidebarItemType? = nil, sidebarName: String? = nil) -> Bool {
        var filter = filter
        var terms = terms
        var projects = projects

        if shouldLoadMain {
            projects = storageOutlineView.getSidebarProjects()

            filter = search.stringValue
            terms = search.stringValue.split(separator: " ")
        }

        return !note.name.isEmpty
            && (filter.isEmpty || isMatched(note: note, terms: terms!).matched)
            && (type == .All && note.project.showInCommon
                || (type != .All && (projects?.contains(where: { note.project.isDescendant(of: $0) }) ?? false))
                || type == .Trash)
            && (type == .Trash && note.isTrash()
                || type != .Trash && !note.isTrash())
    }

    func cleanSearchAndRestoreSelection() {
        UserDataService.instance.searchTrigger = false

        updateTable(search: false) {
            DispatchQueue.main.async {
                if let currentNote = EditTextView.note,
                    let index = self.notesTableView.noteList.firstIndex(of: currentNote)
                {
                    self.notesTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                    self.notesTableView.scrollRowToVisible(index)
                    // Ensure title bar is visible when we have a selected note (unless in PPT mode)
                    if !UserDefaultsManagement.magicPPT {
                        self.titleBarView.isHidden = false
                    }
                }
            }
        }
    }

    // MARK: - Data Sorting and Arrangement
    func reSortByDirection() {
        guard let vc = ViewController.shared() else { return }
        ascendingCheckItem?.state = UserDefaultsManagement.sortDirection ? .off : .on
        descendingCheckItem?.state = UserDefaultsManagement.sortDirection ? .on : .off

        // Sort all notes
        storage.noteList = storage.sortNotes(noteList: storage.noteList, filter: vc.search.stringValue)

        // Sort notes in the current project
        if let filtered = vc.filteredNoteList {
            vc.notesTableView.noteList = storage.sortNotes(noteList: filtered, filter: vc.search.stringValue)
        } else {
            vc.notesTableView.noteList = storage.noteList
        }

        // Remember current selection to avoid unwanted auto-selection after sort
        let currentSelectedRow = vc.notesTableView.selectedRow

        vc.updateTable()
        // Fix post-sort selection: only auto-select first row if nothing was previously selected
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            let selectedRow = vc.notesTableView.selectedRowIndexes.min()
            if selectedRow == nil && currentSelectedRow == -1 {
                vc.notesTableView.selectRowIndexes([0], byExtendingSelection: false)
            }
        }
    }

    public func reSort(note: Note) {
        if !updateViews.contains(note) {
            updateViews.append(note)
        }

        rowUpdaterTimer.invalidate()
        rowUpdaterTimer = Timer.scheduledTimer(timeInterval: 1.2, target: self, selector: #selector(updateTableViews), userInfo: nil, repeats: false)
    }

    public func sortAndMove(note: Note) {
        guard let notes = filteredNoteList else { return }
        guard let srcIndex = notesTableView.noteList.firstIndex(of: note) else { return }

        let resorted = storage.sortNotes(noteList: notes, filter: search.stringValue)
        guard let dstIndex = resorted.firstIndex(of: note) else { return }

        if srcIndex != dstIndex {
            notesTableView.moveRow(at: srcIndex, to: dstIndex)
            notesTableView.noteList = resorted
            filteredNoteList = resorted
        }
    }

    func moveNoteToTop(note index: Int) {
        let isPinned = notesTableView.noteList[index].isPinned
        let position = isPinned ? 0 : notesTableView.countVisiblePinned()
        let note = notesTableView.noteList.remove(at: index)

        notesTableView.noteList.insert(note, at: position)

        notesTableView.reloadRow(note: note)
        notesTableView.moveRow(at: index, to: position)
        notesTableView.scrollRowToVisible(0)
    }

    @objc private func updateTableViews() {
        notesTableView.beginUpdates()
        for note in updateViews {
            notesTableView.reloadRow(note: note)

            if search.stringValue.isEmpty {
                if UserDefaultsManagement.sort == .modificationDate, UserDefaultsManagement.sortDirection == true {
                    if let index = notesTableView.noteList.firstIndex(of: note) {
                        moveNoteToTop(note: index)
                    }
                } else {
                    sortAndMove(note: note)
                }
            }
        }

        updateViews.removeAll()
        notesTableView.endUpdates()
    }

    // MARK: - Selection Management
    @objc func selectNullTableRow(timer: Bool = false) {
        if timer {
            selectRowTimer.invalidate()
            selectRowTimer = Timer.scheduledTimer(timeInterval: TimeInterval(0.2), target: self, selector: #selector(selectRowInstant), userInfo: nil, repeats: false)
            return
        }

        selectRowInstant()
    }

    @objc private func selectRowInstant() {
        // Only auto-select first row when no row is currently selected
        guard notesTableView.selectedRow == -1 else {
            return
        }

        notesTableView.selectRowIndexes([0], byExtendingSelection: false)
        notesTableView.scrollRowToVisible(0)

        if !notesTableView.noteList.isEmpty {
            let note = notesTableView.noteList[0]
            // Avoid filling during note creation to prevent content flashing
            if !UserDataService.instance.shouldBlockEditAreaUpdate() {
                editArea.fill(note: note, options: .forced)
            }
        }
    }

    // MARK: - Data State Management

    public func blockFSUpdates() {
        timer.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(enableFSUpdates), userInfo: nil, repeats: false)

        UserDataService.instance.fsUpdatesDisabled = true
    }

    @objc func enableFSUpdates() {
        UserDataService.instance.fsUpdatesDisabled = false
    }

    // MARK: - CloudKit Data Sync
    #if CLOUDKIT
        func registerKeyValueObserver() {
            let keyStore = NSUbiquitousKeyValueStore()

            NotificationCenter.default.addObserver(self, selector: #selector(ViewController.ubiquitousKeyValueStoreDidChange), name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: keyStore)

            keyStore.synchronize()
        }

        @objc func ubiquitousKeyValueStoreDidChange(notification: NSNotification) {
            if let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
                for key in keys where key == "com.tw93.miaoyan.pins.shared" {
                    let changedNotes = storage.restoreCloudPins()

                    if let notes = changedNotes.added {
                        for note in notes {
                            if let i = notesTableView.getIndex(note) {
                                moveNoteToTop(note: i)
                            }
                        }
                    }

                    if let notes = changedNotes.removed {
                        for note in notes {
                            if let i = notesTableView.getIndex(note) {
                                notesTableView.reloadData(forRowIndexes: [i], columnIndexes: [0])
                            }
                        }
                    }
                }
            }
        }
    #endif

    // MARK: - Utility Methods
    public func contains(tag name: String, in tags: [String]) -> Bool {
        var found = false
        for tag in tags {
            if name == tag || name.starts(with: tag + "/") {
                found = true
                break
            }
        }
        return found
    }

    // MARK: - Sidebar Accessors
    func getSidebarProject() -> Project? {
        if storageOutlineView.selectedRow < 0 {
            return nil
        }

        let sidebarItem = storageOutlineView.item(atRow: storageOutlineView.selectedRow) as? SidebarItem

        if let project = sidebarItem?.project {
            return project
        }

        return nil
    }

    func getSidebarType() -> SidebarItemType? {
        let sidebarItem = storageOutlineView.item(atRow: storageOutlineView.selectedRow) as? SidebarItem

        if let type = sidebarItem?.type {
            return type
        }
        return nil
    }

    func getSidebarItem() -> SidebarItem? {
        if let sidebarItem = storageOutlineView.item(atRow: storageOutlineView.selectedRow) as? SidebarItem {
            return sidebarItem
        }

        return nil
    }

    // MARK: - Search and Input Management
    func focusSearchInput(firstResponder: NSResponder? = nil) {
        DispatchQueue.main.async {
            let index = self.notesTableView.selectedRow > -1 ? self.notesTableView.selectedRow : 0
            self.notesTableView.window?.makeFirstResponder(self.notesTableView)
            self.notesTableView.selectRowIndexes([index], byExtendingSelection: false)
            self.notesTableView.scrollRowToVisible(index)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            _ = self.search.becomeFirstResponder()
        }
    }

    func cleanSearchAndEditArea() {
        search.stringValue = ""
        _ = search.becomeFirstResponder()

        // Keep the current selection when single mode is enabled
        if !UserDefaultsManagement.isSingleMode {
            notesTableView.selectRowIndexes(IndexSet(), byExtendingSelection: false)
            editArea.clear()
        }
    }
}
