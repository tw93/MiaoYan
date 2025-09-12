import Cocoa

// MARK: - Data Management
extension ViewController {

    // MARK: - Search and Filtering

    func updateTable(search: Bool = false, searchText: String? = nil, sidebarItem: SidebarItem? = nil, projects: [Project]? = nil, completion: @escaping () -> Void = {}) {
        var sidebarItem: SidebarItem? = sidebarItem
        var projects: [Project]? = projects
        var sidebarName: String?

        let timestamp = Date().toMillis()

        self.search.timestamp = timestamp
        searchQueue.cancelAllOperations()

        if searchText == nil {
            projects = storageOutlineView.getSidebarProjects()
            sidebarItem = getSidebarItem()
            sidebarName = getSidebarItem()?.getName()
        }

        var filter = searchText ?? self.search.stringValue
        let originalFilter = searchText ?? self.search.stringValue
        filter = originalFilter.lowercased()

        var type = sidebarItem?.type

        // Global search if sidebar not checked
        if type == nil, projects == nil || (projects!.count < 2 && projects!.first!.isRoot) {
            type = .All
        }

        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self] in
            guard let self = self else {
                return
            }

            if let projects = projects {
                for project in projects {
                    self.preLoadNoteTitles(in: project)
                }
            }

            let terms = filter.split(separator: " ")
            let source = self.storage.noteList
            var notes = [Note]()
            let maxResults = search ? 100 : Int.max  // Limit search results for performance

            for note in source {
                if operation.isCancelled {
                    completion()
                    return
                }

                if self.isFit(note: note, filter: filter, terms: terms, projects: projects, type: type, sidebarName: sidebarName) {
                    notes.append(note)

                    // Early exit for search to improve performance
                    if search && notes.count >= maxResults {
                        break
                    }
                }
            }

            let orderedNotesList = self.storage.sortNotes(noteList: notes, filter: filter, project: projects?.first, operation: operation)

            // Check diff
            if self.filteredNoteList == notes, orderedNotesList == self.notesTableView.noteList {
                completion()
                return
            }

            self.filteredNoteList = notes
            self.notesTableView.noteList = orderedNotesList

            if operation.isCancelled {
                completion()
                return
            }

            guard self.notesTableView.noteList.count > 0 else {
                DispatchQueue.main.async {
                    // 在单独模式下不清除编辑器内容
                    if !UserDefaultsManagement.isSingleMode {
                        self.editArea.clear()
                    }
                    self.notesTableView.reloadData()
                    self.refreshMiaoYanNum()
                    completion()
                }
                return
            }

            let _ = self.notesTableView.noteList[0]

            DispatchQueue.main.async {
                // 在单独模式下保存当前选择状态
                let previousSelectedRow = UserDefaultsManagement.isSingleMode ? self.notesTableView.selectedRow : -1

                self.notesTableView.reloadData()
                if search {
                    if self.notesTableView.noteList.count > 0 {
                        if filter.count > 0 {
                            self.selectNullTableRow(timer: true)
                        } else {
                            // 在单独模式下不清除编辑器内容
                            if !UserDefaultsManagement.isSingleMode {
                                self.editArea.clear()
                            }
                        }
                    } else {
                        // 在单独模式下不清除编辑器内容
                        if !UserDefaultsManagement.isSingleMode {
                            self.editArea.clear()
                        }
                    }

                    // 确保搜索后标题栏状态正确
                    self.refreshMiaoYanNum()
                }

                // 在单独模式下恢复选择状态
                if UserDefaultsManagement.isSingleMode, previousSelectedRow != -1, self.notesTableView.noteList.indices.contains(previousSelectedRow) {
                    self.notesTableView.selectRow(previousSelectedRow)
                }

                completion()
            }
        }

        searchQueue.addOperation(operation)
    }

    private func preLoadNoteTitles(in project: Project) {
        if UserDefaultsManagement.sort == .title || project.sortBy == .title {
            _ = storage.noteList.filter {
                $0.project == project
            }
        }
    }

    private func isMatched(note: Note, terms: [Substring]) -> Bool {
        for term in terms {
            if note.name.range(of: term, options: .caseInsensitive, range: nil, locale: nil) != nil {
                continue
            }

            if note.content.string.range(of: term, options: .caseInsensitive, range: nil, locale: nil) != nil {
                continue
            }

            return false
        }

        return true
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
            && (filter.isEmpty || isMatched(note: note, terms: terms!))
            && (type == .All && note.project.showInCommon
                || (type != .All && projects!.contains(note.project)
                    || (note.project.parent != nil && projects!.contains(note.project.parent!)))
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
                    self.emptyEditAreaView.isHidden = true
                }
            }
        }
    }

    // MARK: - Data Sorting and Arrangement

    func reSortByDirection() {
        guard let vc = ViewController.shared() else { return }
        ascendingCheckItem.state = UserDefaultsManagement.sortDirection ? .off : .on
        descendingCheckItem.state = UserDefaultsManagement.sortDirection ? .on : .off

        // Sort all notes
        storage.noteList = storage.sortNotes(noteList: storage.noteList, filter: vc.search.stringValue)

        // Sort notes in the current project
        if let filtered = vc.filteredNoteList {
            vc.notesTableView.noteList = storage.sortNotes(noteList: filtered, filter: vc.search.stringValue)
        } else {
            vc.notesTableView.noteList = storage.noteList
        }

        vc.updateTable()
        // 修复排序后不选中问题
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            let selectedRow = vc.notesTableView.selectedRowIndexes.min()
            if selectedRow == nil {
                vc.notesTableView.selectRowIndexes([0], byExtendingSelection: true)
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

            if search.stringValue.count == 0 {
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
        notesTableView.selectRowIndexes([0], byExtendingSelection: false)
        notesTableView.scrollRowToVisible(0)

        // 确保内容加载和标题栏显示
        if notesTableView.noteList.count > 0 {
            let note = notesTableView.noteList[0]
            editArea.fill(note: note, highlight: true)
        }
    }

    // MARK: - Data State Management

    func refreshMiaoYanNum() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            let messageText = NSLocalizedString("%d MiaoYan", comment: "")

            // 根据当前选择显示不同的数量
            let count: Int
            if let sidebarItem = self.getSidebarItem() {
                if sidebarItem.type == .All {
                    // 显示所有非垃圾箱笔记数量
                    count = self.storage.noteList.filter { !$0.isTrash() }.count
                } else {
                    // 显示当前过滤视图的数量
                    count = self.notesTableView.noteList.count
                }
            } else {
                // 默认显示当前视图数量
                count = self.notesTableView.noteList.count
            }

            self.miaoYanText.stringValue = String(format: messageText, count)
        }
    }

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
                for key in keys {
                    if key == "com.tw93.miaoyan.pins.shared" {
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
            self.notesTableView.selectRowIndexes([index], byExtendingSelection: true)
            self.notesTableView.scrollRowToVisible(index)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.search.becomeFirstResponder()
        }
    }

    func cleanSearchAndEditArea() {
        search.stringValue = ""
        search.becomeFirstResponder()

        // 在单独模式下不清除选择状态
        if !UserDefaultsManagement.isSingleMode {
            notesTableView.selectRowIndexes(IndexSet(), byExtendingSelection: false)
            editArea.clear()
        }
    }
}
