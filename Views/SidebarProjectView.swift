import Carbon.HIToolbox
import Cocoa
import Foundation
import TelemetryDeck

class SidebarProjectView: NSOutlineView,
    NSOutlineViewDelegate,
    NSOutlineViewDataSource,
    NSMenuItemValidation
{
    var sidebarItems: [Any]?
    var viewDelegate: ViewController?

    private var storage = Storage.sharedInstance()
    public var isLaunch = true

    private var selectedProjects = [Project]()

    private var lastSelectedRow: Int?

    override func awakeFromNib() {
        super.awakeFromNib()
        setDraggingSourceOperationMask(.move, forLocal: true)
        registerForDraggedTypes([
            NSPasteboard.PasteboardType(rawValue: "public.data"),
            NSPasteboard.PasteboardType(rawValue: "notesTable"),
            NSPasteboard.PasteboardType(rawValue: "SidebarProjectReorder"),
        ])
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let sidebarItem = getSidebarItem() else {
            return false
        }

        if menuItem.title == NSLocalizedString("Show in Finder", comment: "") {
            if let sidebarItem = getSidebarItem() {
                return sidebarItem.project != nil || sidebarItem.isTrash()
            }
        }

        if menuItem.title == NSLocalizedString("Rename Folder", comment: "") {
            if sidebarItem.isTrash() {
                return false
            }

            if let project = sidebarItem.project {
                menuItem.isHidden = project.isRoot
            }

            if let project = sidebarItem.project, !project.isDefault {
                return true
            }
        }

        if menuItem.title == NSLocalizedString("Delete Folder", comment: "") {
            if sidebarItem.isTrash() {
                return false
            }

            if sidebarItem.project != nil {
                menuItem.title = NSLocalizedString("Delete Folder", comment: "")
            }

            if let project = sidebarItem.project, !project.isDefault {
                return true
            }
        }

        return false
    }

    override func keyDown(with event: NSEvent) {
        guard let vc = ViewController.shared() else {
            return
        }
        if event.modifierFlags.contains(.command), event.modifierFlags.contains(.shift), event.keyCode == kVK_ANSI_N {
            addProject("")
            return
        }

        if event.modifierFlags.contains(.option), event.modifierFlags.contains(.command), event.keyCode == kVK_ANSI_R {
            revealInFinder("")
            return
        }

        if event.modifierFlags.contains(.shift), event.keyCode == kVK_F6 {
            renameMenu("")
            return
        }

        if event.modifierFlags.contains(.command), event.modifierFlags.contains(.shift), event.keyCode == kVK_Delete {
            deleteMenu("")
            return
        }

        if event.keyCode == kVK_RightArrow {
            if let fr = window?.firstResponder, fr.isKind(of: NSTextView.self) {
                super.keyUp(with: event)
                return
            }

            vc.notesTableView.window?.makeFirstResponder(vc.notesTableView)
            // Don't auto-select any note, let user explicitly choose with arrow keys or right arrow
        }
        // Tab to search
        if event.keyCode == 48 {
            viewDelegate?.search.becomeFirstResponder()
            return
        }
        super.keyDown(with: event)
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let vc = ViewController.shared() else {
            return false
        }
        let board = info.draggingPasteboard

        // Handle project reordering
        if let stringData = board.string(forType: .string),
            stringData.hasPrefix("SIDEBAR_REORDER:")
        {
            return handleProjectReordering(stringData: stringData, index: index)
        }

        guard let sidebarItem = item as? SidebarItem else {
            return false
        }

        return handleItemDrop(sidebarItem: sidebarItem, board: board, vc: vc)
    }

    private func handleProjectReordering(stringData: String, index: Int) -> Bool {
        let components = stringData.components(separatedBy: ":")
        guard components.count >= 3,
            let sourceIndex = Int(components[1]),
            let sidebarItems = sidebarItems
        else {
            return false
        }

        guard isValidReorderOperation(sourceIndex: sourceIndex, targetIndex: index, sidebarItems: sidebarItems) else {
            return false
        }

        return executeReorderOperation(sourceIndex: sourceIndex, targetIndex: index, sidebarItems: sidebarItems)
    }

    private func isValidReorderOperation(sourceIndex: Int, targetIndex: Int, sidebarItems: [Any]) -> Bool {
        // Make sure we have valid indices
        guard sourceIndex >= 0 && sourceIndex < sidebarItems.count && targetIndex >= 0 && targetIndex <= sidebarItems.count else {
            return false
        }

        // Don't allow moving before first item (MiaoYan)
        guard targetIndex > 0 else {
            return false
        }

        // Don't allow moving after trash item (if it exists)
        if targetIndex == sidebarItems.count,
            let lastItem = sidebarItems[sidebarItems.count - 1] as? SidebarItem,
            lastItem.isTrash()
        {
            return false
        }

        return true
    }

    private func executeReorderOperation(sourceIndex: Int, targetIndex: Int, sidebarItems: [Any]) -> Bool {
        var mutableSidebarItems = sidebarItems

        // Remove the item from its current position
        let movedItem = mutableSidebarItems.remove(at: sourceIndex)

        // Insert it at the new position (adjust index if we moved an item from before the target)
        let insertIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        mutableSidebarItems.insert(movedItem, at: insertIndex)

        // Update the sidebar items
        self.sidebarItems = mutableSidebarItems

        // Save the new order to UserDefaults
        saveSidebarOrder(mutableSidebarItems)

        // Reload the outline view
        reloadData()

        // Maintain selection
        selectRowIndexes([insertIndex], byExtendingSelection: false)

        // Update UserDefaultsManagement.lastProject to reflect new position
        UserDefaultsManagement.lastProject = insertIndex

        return true
    }

    private func handleItemDrop(sidebarItem: SidebarItem, board: NSPasteboard, vc: ViewController) -> Bool {
        switch sidebarItem.type {
        case .Category, .Trash:
            return handleCategoryOrTrashDrop(sidebarItem: sidebarItem, board: board, vc: vc)
        default:
            return false
        }
    }

    private func handleCategoryOrTrashDrop(sidebarItem: SidebarItem, board: NSPasteboard, vc: ViewController) -> Bool {
        // Handle notes table data
        if let data = board.data(forType: NSPasteboard.PasteboardType(rawValue: "notesTable")) {
            return handleNotesTableDrop(data: data, sidebarItem: sidebarItem, vc: vc)
        }

        // Handle file URLs
        guard let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
            let project = sidebarItem.project
        else {
            return false
        }

        return handleFileURLsDrop(urls: urls, project: project, vc: vc)
    }

    private func handleNotesTableDrop(data: Data, sidebarItem: SidebarItem, vc: ViewController) -> Bool {
        do {
            guard let rows = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSSet.self, NSNumber.self, NSIndexSet.self], from: data) as? IndexSet else {
                print("Failed to unarchive IndexSet")
                return false
            }

            let notes = rows.map { vc.notesTableView.noteList[$0] }

            if let project = sidebarItem.project {
                vc.move(notes: notes, project: project)
            } else if sidebarItem.isTrash() {
                moveNotesToTrash(notes: notes, vc: vc)
            }

            return true
        } catch {
            print("Failed to unarchive IndexSet: \(error)")
            return false
        }
    }

    private func moveNotesToTrash(notes: [Note], vc: ViewController) {
        vc.editArea.clear()
        vc.storage.removeNotes(notes: notes) { _ in
            DispatchQueue.main.async {
                vc.storageOutlineView.reloadSidebar()
                vc.notesTableView.removeByNotes(notes: notes)
            }
        }
    }

    private func handleFileURLsDrop(urls: [URL], project: Project, vc: ViewController) -> Bool {
        for url in urls {
            var isDirectory = ObjCBool(true)
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                isDirectory.boolValue,
                !url.path.contains(".textbundle")
            {
                handleDirectoryDrop(url: url, project: project, vc: vc)
            } else {
                _ = vc.copy(project: project, url: url)
            }
        }
        return true
    }

    private func handleDirectoryDrop(url: URL, project: Project, vc: ViewController) {
        let newSub = project.url.appendingPathComponent(url.lastPathComponent, isDirectory: true)
        let newProject = Project(url: newSub, parent: project)
        newProject.create()

        _ = storage.add(project: newProject)
        reloadSidebar()

        let validFiles = storage.readDirectory(url)
        for file in validFiles {
            _ = vc.copy(project: newProject, url: file.url)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let board = info.draggingPasteboard

        // Handle project reordering - check if the string has our encoded format
        if let stringData = board.string(forType: .string),
            stringData.hasPrefix("SIDEBAR_REORDER:")
        {
            let components = stringData.components(separatedBy: ":")
            if components.count >= 3, Int(components[1]) != nil {
                // Allow the move
                return .move
            }
        }

        guard let sidebarItem = item as? SidebarItem else {
            return NSDragOperation()
        }
        switch sidebarItem.type {
        case .Trash:
            if let data = board.data(forType: NSPasteboard.PasteboardType(rawValue: "notesTable")), !data.isEmpty {
                return .copy
            }
        case .Category:
            guard sidebarItem.isSelectable() else {
                break
            }

            if let data = board.data(forType: NSPasteboard.PasteboardType(rawValue: "notesTable")), !data.isEmpty {
                return .move
            }

            if let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
                return .copy
            }
        default:
            break
        }

        return NSDragOperation()
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let sidebar = sidebarItems, item == nil {
            return sidebar.count
        }

        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if item is SidebarItem {
            return 34
        }
        return 24
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        false
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let sidebar = sidebarItems, item == nil {
            return sidebar[index]
        }

        return ""
    }

    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        item
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cell = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "DataCell"), owner: self) as! SidebarCellView

        if let si = item as? SidebarItem {
            cell.textField?.stringValue = si.name

            cell.label.font = UserDefaultsManagement.nameFont
            cell.label.addCharacterSpacing()

            switch si.type {
            case .All:
                cell.icon.image = NSImage(imageLiteralResourceName: "home.png")
                cell.icon.isHidden = false
                cell.label.frame.origin.x = 24

            case .Trash:
                cell.icon.image = NSImage(imageLiteralResourceName: "trash.png")
                cell.icon.isHidden = false
                cell.label.frame.origin.x = 24

            case .Category:
                cell.icon.image = NSImage(imageLiteralResourceName: "repository.png")
                cell.icon.isHidden = false
                cell.label.frame.origin.x = 24
            }
        }
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let sidebarItem = item as? SidebarItem else {
            return false
        }

        return sidebarItem.isSelectable()
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        SidebarTableRowView(frame: NSRect.zero)
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let sidebarItem = item as? SidebarItem else { return nil }

        // Only allow Category type items to be dragged, not Trash items
        if sidebarItem.type != .Category || sidebarItem.isTrash() {
            return nil
        }

        // Find the index of this item
        let itemIndex = outlineView.row(forItem: item)
        guard itemIndex >= 0 else { return nil }

        guard sidebarItems != nil else { return nil }

        // Don't allow dragging the first item (MiaoYan - .All type)
        if itemIndex == 0 {
            return nil
        }

        // Check if this is a Trash item (can appear anywhere when there are deleted files)
        if sidebarItem.isTrash() {
            return nil
        }

        let pasteboardItem = NSPasteboardItem()
        let encodedData = "SIDEBAR_REORDER:\(itemIndex):\(sidebarItem.name)"
        pasteboardItem.setString(encodedData, forType: .string)

        return pasteboardItem
    }

    override func selectRowIndexes(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
        guard indexes.first != nil else {
            return
        }
        super.selectRowIndexes(indexes, byExtendingSelection: extend)
    }

    private func isChangedSelectedProjectsState() -> Bool {
        var qtyChanged = false
        if selectedProjects.isEmpty {
            for i in selectedRowIndexes {
                if let si = item(atRow: i) as? SidebarItem, let project = si.project {
                    selectedProjects.append(project)
                    qtyChanged = true
                }
            }
        } else {
            var new = [Project]()
            for i in selectedRowIndexes {
                if let si = item(atRow: i) as? SidebarItem, let project = si.project {
                    new.append(project)
                    if !selectedProjects.contains(project) {
                        qtyChanged = true
                    }
                }
            }
            selectedProjects = new

            if new.isEmpty {
                qtyChanged = true
            }
        }

        return qtyChanged
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let vd = viewDelegate else {
            return
        }
        if UserDataService.instance.isNotesTableEscape {
            UserDataService.instance.isNotesTableEscape = false
        }

        guard let sidebarItems = sidebarItems else {
            return
        }

        lastSelectedRow = selectedRow

        if let view = notification.object as? NSOutlineView {
            let sidebar = sidebarItems
            let i = view.selectedRow

            if sidebar.indices.contains(i), let item = sidebar[i] as? SidebarItem {
                if UserDataService.instance.lastType == item.type.rawValue, UserDataService.instance.lastProject == item.project?.url,
                    UserDataService.instance.lastName == item.name
                {
                    return
                }

                UserDefaultsManagement.lastProject = i

                UserDataService.instance.lastType = item.type.rawValue
                UserDataService.instance.lastProject = item.project?.url
                UserDataService.instance.lastName = item.name
            }

            // Don't clear edit area during launch to prevent flashing
            if !isLaunch {
                // 在单独模式下不清除编辑器内容
                if !UserDefaultsManagement.isSingleMode {
                    vd.editArea.clear()
                }
                vd.search.stringValue = ""
                // Save current scroll position when switching projects
                vd.notesTableView.saveScrollPosition()
            }

            guard !UserDataService.instance.skipSidebarSelection else {
                UserDataService.instance.skipSidebarSelection = false
                return
            }

            vd.updateTable {
                if self.isLaunch {
                    // During launch, restore note selection
                    if let url = UserDefaultsManagement.lastSelectedURL,
                        let lastNote = vd.storage.getBy(url: url),
                        let i = vd.notesTableView.getIndex(lastNote)
                    {
                        vd.notesTableView.selectRow(i)
                        // Restore scroll position instead of scrolling to visible row
                        vd.notesTableView.restoreScrollPosition()
                    } else if !vd.notesTableView.noteList.isEmpty {
                        vd.focusTable()
                    }
                    self.isLaunch = false
                } else {
                    DispatchQueue.main.async {
                        // 在单独模式下不清除笔记选择
                        if !UserDefaultsManagement.isSingleMode {
                            vd.notesTableView.deselectNotes()
                        }
                    }
                }
            }
        }
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        if clickedRow > -1 {
            selectRowIndexes([clickedRow], byExtendingSelection: false)

            for item in menu.items {
                item.isHidden = !validateMenuItem(item)
            }
        }
    }

    @IBAction func revealInFinder(_ sender: Any) {
        guard let si = getSidebarItem(), let p = si.project else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([p.url])

        TelemetryDeck.signal("Action.RevealInFinder")
    }

    @IBAction func renameMenu(_ sender: Any) {
        guard let vc = ViewController.shared(), let v = vc.storageOutlineView else {
            return
        }

        let selected = v.selectedRow
        guard let si = v.sidebarItems,
            si.indices.contains(selected)
        else {
            return
        }

        guard
            let sidebarItem = si[selected] as? SidebarItem,
            sidebarItem.type == .Category,
            let projectRow = v.rowView(atRow: selected, makeIfNecessary: false),
            let cell = projectRow.view(atColumn: 0) as? SidebarCellView
        else {
            return
        }

        cell.label.isEditable = true
        cell.label.becomeFirstResponder()
    }

    @IBAction func deleteMenu(_ sender: Any) {
        guard let vc = ViewController.shared(), let v = vc.storageOutlineView else {
            return
        }

        let selected = v.selectedRow
        guard let si = v.sidebarItems, si.indices.contains(selected) else {
            return
        }

        guard let sidebarItem = si[selected] as? SidebarItem, let project = sidebarItem.project, !project.isDefault, sidebarItem.type != .All, sidebarItem.type != .Trash else {
            return
        }

        if !project.isRoot, sidebarItem.type == .Category {
            guard let w = v.superview?.window else {
                return
            }

            let alert = NSAlert()
            let messageText = NSLocalizedString("Are you sure you want to remove project \"%@\" and all files inside?", comment: "")

            alert.messageText = String(format: messageText, project.label)
            alert.informativeText = NSLocalizedString("This action cannot be undone.", comment: "Delete menu")
            alert.addButton(withTitle: NSLocalizedString("Remove", comment: "Delete menu"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Delete menu"))
            alert.beginSheetModal(for: w) { (returnCode: NSApplication.ModalResponse) in
                if returnCode == NSApplication.ModalResponse.alertFirstButtonReturn {
                    guard let resultingItemUrl = Storage.sharedInstance().trashItem(url: project.url) else {
                        return
                    }

                    do {
                        try FileManager.default.moveItem(at: project.url, to: resultingItemUrl)

                        v.removeProject(project: project)

                        vc.updateTable {
                            DispatchQueue.main.async {
                                vc.storageOutlineView.selectRowIndexes([0], byExtendingSelection: false)
                            }
                        }
                    } catch {
                        print(error)
                    }
                }
            }
            return
        }
        v.removeProject(project: project)
    }

    @IBAction func addProject(_ sender: Any) {
        let project = Storage.sharedInstance().getMainProject()
        guard let window = MainWindowController.shared() else {
            return
        }

        let alert = NSAlert()
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.focusRingType = .none
        alert.messageText = NSLocalizedString("New project", comment: "")
        alert.accessoryView = field
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("Add", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.beginSheetModal(for: window) { (returnCode: NSApplication.ModalResponse) in
            if returnCode == NSApplication.ModalResponse.alertFirstButtonReturn {
                self.addChild(field: field, project: project)
            }
        }

        field.becomeFirstResponder()
        TelemetryDeck.signal("Action.NewProject")
    }

    @IBAction func openSettings(_ sender: NSMenuItem) {
        guard let vc = ViewController.shared() else {
            return
        }

        vc.openProjectViewSettings(sender)
        TelemetryDeck.signal("Action.OpenSetting")
    }

    private func removeProject(project: Project) {
        storage.removeBy(project: project)

        viewDelegate?.fsManager?.restart()
        viewDelegate?.cleanSearchAndEditArea()

        sidebarItems = Sidebar().getList()
        reloadData()
    }

    private func addChild(field: NSTextField, project: Project) {
        let value = field.stringValue
        guard !value.isEmpty else {
            return
        }

        do {
            let projectURL = project.url.appendingPathComponent(value, isDirectory: true)
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: false, attributes: nil)

            let newProject = Project(url: projectURL, parent: project.getParent())
            _ = storage.add(project: newProject)
            reloadSidebar()
        } catch {
            let alert = NSAlert()
            alert.messageText = error.localizedDescription
            alert.runModal()
        }
    }

    private func addRoot() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = false
        openPanel.begin { result in
            if result == NSApplication.ModalResponse.OK {
                guard let url = openPanel.url else {
                    return
                }

                guard !self.storage.projectExist(url: url) else {
                    return
                }
                let newProject = Project(url: url, isRoot: true)
                let projects = self.storage.add(project: newProject)
                for project in projects {
                    self.storage.loadLabel(project)
                }

                self.reloadSidebar()
            }
        }
    }

    public func getSidebarProjects() -> [Project]? {
        guard let vc = ViewController.shared(), let v = vc.storageOutlineView else {
            return nil
        }

        var projects = [Project]()
        for i in v.selectedRowIndexes {
            if let si = item(atRow: i) as? SidebarItem, let project = si.project {
                projects.append(project)
            }
        }

        if !projects.isEmpty {
            return projects
        }

        if let root = Storage.sharedInstance().getRootProject() {
            return [root]
        }
        return nil
    }

    public func selectNext() {
        let i = selectedRow + 1
        guard let si = sidebarItems, si.indices.contains(i) else {
            return
        }

        if let next = si[i] as? SidebarItem {
            if next.project == nil {
                let j = i + 1

                guard let si = sidebarItems, si.indices.contains(j) else {
                    return
                }

                if si[j] is SidebarItem {
                    selectRowIndexes([j], byExtendingSelection: false)
                    return
                }

                return
            }
        }

        selectRowIndexes([i], byExtendingSelection: false)
    }

    public func selectPrev() {
        let i = selectedRow - 1
        guard let si = sidebarItems, si.indices.contains(i) else {
            return
        }

        if let next = si[i] as? SidebarItem {
            if next.project == nil {
                let j = i - 1

                guard let si = sidebarItems, si.indices.contains(j) else {
                    return
                }

                if si[j] is SidebarItem {
                    selectRowIndexes([j], byExtendingSelection: false)
                    return
                }

                return
            }
        }

        selectRowIndexes([i], byExtendingSelection: false)
    }

    private func getSidebarItem() -> SidebarItem? {
        guard let vc = ViewController.shared(), let v = vc.storageOutlineView else {
            return nil
        }

        let selected = v.selectedRow
        guard let si = v.sidebarItems,
            si.indices.contains(selected)
        else {
            return nil
        }

        let sidebarItem = si[selected] as? SidebarItem
        return sidebarItem
    }

    @objc public func reloadSidebar() {
        guard let vc = ViewController.shared() else {
            return
        }
        vc.fsManager?.restart()
        vc.loadMoveMenu()

        let selected = vc.storageOutlineView.selectedRow
        vc.storageOutlineView.sidebarItems = Sidebar().getList()
        vc.storageOutlineView.reloadData()
        vc.storageOutlineView.selectRowIndexes([selected], byExtendingSelection: false)
    }

    private func saveSidebarOrder(_ items: [Any]) {
        var projectPaths: [String] = []

        // Extract project paths from Category items, preserving order
        for item in items {
            if let sidebarItem = item as? SidebarItem,
                sidebarItem.type == .Category,
                let project = sidebarItem.project
            {
                projectPaths.append(project.url.path)
            }
        }

        UserDefaults.standard.set(projectPaths, forKey: "SidebarProjectOrder")
        UserDefaults.standard.synchronize()
    }
}
