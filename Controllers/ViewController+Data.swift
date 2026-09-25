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

/// A note as the background matcher sees it: plain values only, so reading and
/// lowercasing bodies can leave the main thread without touching `Note`.
struct NoteSearchCandidate: Sendable {
    let index: Int
    /// Lowercased file name without the extension, so `.` or `md` no longer
    /// matches every note through `.md`.
    let title: String
    let url: URL
    /// The in-memory text of a loaded note, which can be newer than the file.
    /// Nil means read the file.
    let loadedText: String?
}

enum NoteContentMatcher {
    /// Matching candidates in their original order with a priority, stopping
    /// after `limit`. Runs off the main thread.
    nonisolated static func match(
        _ candidates: [NoteSearchCandidate],
        terms: [String],
        limit: Int,
        isCancelled: () -> Bool
    ) -> [(index: Int, priority: Int)] {
        var matches: [(index: Int, priority: Int)] = []
        for candidate in candidates {
            if isCancelled() { return [] }
            let body = {
                candidate.loadedText ?? (try? String(contentsOf: candidate.url, encoding: .utf8)) ?? ""
            }
            guard let priority = priority(title: candidate.title, body: body, terms: terms) else { continue }
            matches.append((candidate.index, priority))
            if matches.count >= limit { break }
        }
        return matches
    }

    /// 4 when every term is in the title, then 3, 2, 1 as more of the match
    /// comes from the body; nil when some term is in neither. `body` is only
    /// read when the title alone does not settle it.
    nonisolated static func priority(title: String, body: () -> String, terms: [String]) -> Int? {
        guard !terms.isEmpty else { return 0 }

        let titleMatches = terms.filter { title.contains($0) }.count
        if titleMatches == terms.count { return 4 }

        let content = body().lowercased()
        var contentMatches = 0
        for term in terms where !title.contains(term) {
            guard content.contains(term) else { return nil }
            contentMatches += 1
        }

        if titleMatches > contentMatches { return 3 }
        return titleMatches > 0 ? 2 : 1
    }
}

extension Note {
    fileprivate var searchTitle: String {
        (title.isEmpty ? url.deletingPathExtension().lastPathComponent : title).lowercased()
    }
}

/// Lets the background matcher poll the search operation's cancellation.
/// `Operation.isCancelled` is documented as thread-safe.
private struct SearchCancellation: @unchecked Sendable {
    private let operation: Operation
    init(_ operation: Operation) { self.operation = operation }
    var isCancelled: Bool { operation.isCancelled }
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
                if project.isTrash {
                    storage.retireMissingNotes(in: project)
                }
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

        let singleModeUrl =
            UserDefaultsManagement.singleModeURL
            ?? URL(fileURLWithPath: UserDefaultsManagement.singleModePath).resolvingSymlinksInPath()
        let isSingleModeDirectory =
            UserDefaultsManagement.isSingleMode && FileManager.default.directoryExists(atUrl: singleModeUrl)

        if searchText == nil,
            UserDefaultsManagement.isSingleMode,
            finalProjects == nil
        {
            if !FileManager.default.directoryExists(atUrl: singleModeUrl),
                let project = storage.getProjectBy(url: singleModeUrl)
            {
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

        if searchText == nil,
            isSingleModeDirectory,
            finalSidebarItem?.type == .All,
            let rootProject = storage.getRootProject(),
            rootProject.url == singleModeUrl
        {
            finalProjects = [rootProject] + storage.getChildProjects(project: rootProject)
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

        // The folder check is cheap and rules out most of the library, so it
        // runs before any text is compared.
        let scoped = storage.noteList.filter {
            isInScope(note: $0, projects: searchParams.projects, type: searchParams.type)
        }
        let terms = searchParams.filter.split(separator: " ").map { $0.lowercased() }

        guard !terms.isEmpty else {
            let results = scoped.map { NoteSearchResult(note: $0, priority: 0, modifiedAt: $0.modifiedLocalAt) }
            finishSearch(results: results, searchParams: searchParams, isSearch: isSearch, operation: operation, completion: completion)
            return
        }

        // Only a note whose title leaves the query open needs its body, and
        // only a loaded one hands over its in-memory text; the rest are read
        // from disk by the background matcher.
        let candidates = scoped.enumerated().map { index, note in
            let title = note.searchTitle
            let needsBody = !terms.allSatisfy { title.contains($0) }
            return NoteSearchCandidate(
                index: index,
                title: title,
                url: note.url,
                loadedText: needsBody && note.isContentLoaded ? note.content.string : nil
            )
        }
        let limit = isSearch ? 100 : Int.max
        let cancellation = SearchCancellation(operation)

        Task { @MainActor [weak self] in
            let matches = await Task.detached(priority: .userInitiated) {
                NoteContentMatcher.match(candidates, terms: terms, limit: limit, isCancelled: { cancellation.isCancelled })
            }.value

            guard let self, !operation.isCancelled else {
                completion()
                return
            }
            let results = matches.map {
                NoteSearchResult(note: scoped[$0.index], priority: $0.priority, modifiedAt: scoped[$0.index].modifiedLocalAt)
            }
            self.finishSearch(results: results, searchParams: searchParams, isSearch: isSearch, operation: operation, completion: completion)
        }
    }

    private func finishSearch(results notesWithPriority: [NoteSearchResult], searchParams: SearchParameters, isSearch: Bool, operation: Operation, completion: @escaping () -> Void) {
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
        WikilinkIndex.shared.rebuild(notes: orderedNotesList)

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

    private func isInScope(note: Note, projects: [Project]?, type: SidebarItemType?) -> Bool {
        guard !note.name.isEmpty else { return false }
        guard type == .Trash ? note.isTrash() : !note.isTrash() else { return false }
        if type == .Trash { return true }
        if projects?.contains(where: { note.project.isDescendant(of: $0) }) ?? false { return true }
        return type == .All && note.project.showInCommon
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

        guard isInScope(note: note, projects: projects, type: type) else { return false }
        guard !filter.isEmpty, let terms, !terms.isEmpty else { return true }

        return NoteContentMatcher.priority(
            title: note.searchTitle,
            body: {
                note.ensureContentLoaded()
                return note.content.string
            },
            terms: terms.map { $0.lowercased() }
        ) != nil
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
                    if !self.sessionMagicPPTMode {
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
        if let note = EditTextView.note {
            fsManager?.recheckNote(note)
        }
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
                for key in keys where key == AppIdentifier.cloudPinsKey {
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
