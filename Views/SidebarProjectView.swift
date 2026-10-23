import Carbon.HIToolbox
import Cocoa
import Foundation

@MainActor
private enum UIConstants {
    static let brandRowHeight: CGFloat = 52
    static let defaultRowHeight: CGFloat = 32
}

@MainActor
private enum MenuTitles {
    static let showInFinder = I18n.str("Show in Finder")
    static let renameFolder = I18n.str("Rename Folder")
    static let deleteFolder = I18n.str("Delete Folder")
    static let newSubfolder = I18n.str("New Subfolder")
    static let openInTerminal = I18n.str("Open in Terminal")
}

private enum DragDropTypes {
    static let publicData = NSPasteboard.PasteboardType(rawValue: "public.data")
    static let notesTable = NSPasteboard.PasteboardType(rawValue: "notesTable")
    static let sidebarReorder = NSPasteboard.PasteboardType(rawValue: "SidebarProjectReorder")
}

private struct KeyboardShortcut {
    let modifiers: NSEvent.ModifierFlags
    let keyCode: UInt16
    let action: () -> Void

    func matches(_ event: NSEvent) -> Bool {
        return event.modifierFlags.contains(modifiers) && event.keyCode == keyCode
    }
}

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
        MainActor.assumeIsolated { [self] in
            setDraggingSourceOperationMask(.move, forLocal: true)
            registerForDraggedTypes([
                DragDropTypes.publicData,
                DragDropTypes.notesTable,
                DragDropTypes.sidebarReorder,
            ])
        }
    }

    override func tile() {
        super.tile()
        guard let clipView = superview as? NSClipView,
            let column = tableColumns.first
        else { return }

        let clipWidth = clipView.bounds.width
        guard clipWidth > 0 else { return }

        if abs(frame.width - clipWidth) > 0.5 {
            setFrameSize(NSSize(width: clipWidth, height: frame.height))
        }
        if abs(column.width - clipWidth) > 0.5 {
            column.width = clipWidth
        }

        let origin = clipView.bounds.origin
        if origin.x != 0 {
            clipView.scroll(to: NSPoint(x: 0, y: origin.y))
            enclosingScrollView?.reflectScrolledClipView(clipView)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let sidebarItem = getSidebarItem() else {
            return false
        }

        switch menuItem.action {
        case #selector(revealInFinder(_:)):
            return sidebarItem.project != nil || sidebarItem.isTrash()

        case #selector(renameMenu(_:)):
            return validateRenameMenuItem(sidebarItem: sidebarItem, menuItem: menuItem)

        case #selector(moveFolderMenu(_:)):
            guard let project = sidebarItem.project else { return false }
            return sidebarItem.type == .Category && !project.isRoot && !project.isDefault && !project.isTrash

        case #selector(deleteMenu(_:)):
            return validateDeleteMenuItem(sidebarItem: sidebarItem, menuItem: menuItem)

        case #selector(newSubfolder(_:)):
            return sidebarItem.type == .Category

        default:
            break
        }

        // openInTerminal: lives in ViewController; match by title since we can't use #selector here
        if menuItem.title == MenuTitles.openInTerminal {
            return !sidebarItem.isTrash() && UserDefaultsManagement.storageUrl != nil
        }

        return false
    }

    private func validateRenameMenuItem(sidebarItem: SidebarItem, menuItem: NSMenuItem) -> Bool {
        guard !sidebarItem.isTrash() else { return false }

        if let project = sidebarItem.project {
            menuItem.isHidden = project.isRoot
            return !project.isDefault
        }
        return false
    }

    private func validateDeleteMenuItem(sidebarItem: SidebarItem, menuItem: NSMenuItem) -> Bool {
        guard !sidebarItem.isTrash() else { return false }

        if sidebarItem.project != nil {
            menuItem.title = MenuTitles.deleteFolder
        }

        return sidebarItem.project?.isDefault == false
    }

    override func keyDown(with event: NSEvent) {
        guard let vc = AppContext.shared.viewController else {
            return
        }

        if handleKeyboardShortcuts(event) {
            return
        }

        if handleNavigationKeys(event, vc: vc) {
            return
        }

        super.keyDown(with: event)
    }

    private func handleKeyboardShortcuts(_ event: NSEvent) -> Bool {
        let shortcuts: [KeyboardShortcut] = [
            KeyboardShortcut(modifiers: [.command, .shift], keyCode: UInt16(kVK_ANSI_N)) { self.addProject("") },
            KeyboardShortcut(modifiers: [.option, .command], keyCode: UInt16(kVK_ANSI_R)) { self.revealInFinder("") },
            KeyboardShortcut(modifiers: [.shift], keyCode: UInt16(kVK_F6)) { self.renameMenu("") },
            KeyboardShortcut(modifiers: [.command, .shift], keyCode: UInt16(kVK_Delete)) { self.deleteMenu("") },
        ]

        for shortcut in shortcuts where shortcut.matches(event) {
            shortcut.action()
            return true
        }
        return false
    }

    private func handleNavigationKeys(_ event: NSEvent, vc: ViewController) -> Bool {
        switch Int(event.keyCode) {
        case Int(kVK_RightArrow):
            if let fr = window?.firstResponder, fr.isKind(of: NSTextView.self) {
                super.keyUp(with: event)
                return true
            }
            vc.notesTableView.window?.makeFirstResponder(vc.notesTableView)
            return false

        case 48:  // Tab key
            _ = viewDelegate?.search.becomeFirstResponder()
            return true

        default:
            return false
        }
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let vc = AppContext.shared.viewController else {
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

        // Folders stay below the brand and All Notes
        let leadingFixed = sidebarItems.prefix { ($0 as? SidebarItem)?.type != .Category }.count
        guard targetIndex >= leadingFixed else {
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
                AppDelegate.trackError(NSError(domain: "SidebarProjectView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to unarchive IndexSet"]), context: "SidebarProjectView.handleNotesTableDrop")
                return false
            }

            let notes = rows.compactMap { index -> Note? in
                guard index < vc.notesTableView.noteList.count else { return nil }
                return vc.notesTableView.noteList[index]
            }

            if let project = sidebarItem.project {
                vc.move(notes: notes, project: project)
            } else if sidebarItem.isTrash() {
                moveNotesToTrash(notes: notes, vc: vc)
            }

            return true
        } catch {
            AppDelegate.trackError(error, context: "SidebarProjectView.handleNotesTableDrop")
            return false
        }
    }

    private func moveNotesToTrash(notes: [Note], vc: ViewController) {
        let selectedRow = vc.notesTableView.selectedRowIndexes.min() ?? -1
        vc.storage.removeNotes(
            notes: notes,
            didRemove: { removedNotes in
                vc.notesTableView.removeAndReselect(
                    notes: removedNotes,
                    originalRow: selectedRow)
            }
        ) { _ in
            DispatchQueue.main.async {
                vc.storageOutlineView.reloadSidebar()
                if vc.notesTableView.noteList.isEmpty {
                    vc.editArea.clear()
                }
            }
        }
    }

    private func handleFileURLsDrop(urls: [URL], project: Project, vc: ViewController) -> Bool {
        for url in urls {
            var isDirectory = ObjCBool(true)
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                isDirectory.boolValue
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

    // MARK: - Helper Methods

    private func configureCellLayout(_ cell: SidebarCellView, baseFont: NSFont) {
        let defaultIconSize: CGFloat = 20
        let defaultSpacing: CGFloat = 6
        let defaultIconLeading: CGFloat = 1

        updateIconLeading(cell, leading: defaultIconLeading)
        adjustIconSize(cell, size: defaultIconSize)
        setupBasicCellAppearance(cell, baseFont: baseFont)
        updateLabelVerticalNudge(cell, nudge: Theme.Metrics.sidebarStandardLabelVerticalNudge)
        updateLabelSpacing(cell, spacing: defaultSpacing)
        alignContentVertically(cell)
    }

    private func alignContentVertically(_ cell: SidebarCellView) {
        cell.layoutSubtreeIfNeeded()

        cell.icon.translatesAutoresizingMaskIntoConstraints = false
        cell.label.translatesAutoresizingMaskIntoConstraints = false

        // Keep the view frames on the same center line. CJK ink is adjusted by
        // SidebarLabelCell drawing, so the constraints remain stable.
        let iconOffset = Theme.Metrics.sidebarStandardIconOffsetY
        let labelOffset = Theme.Metrics.sidebarLabelOffsetY

        var hasIconCenterY = false
        var hasLabelCenterY = false

        for constraint in cell.constraints {
            guard constraint.firstAttribute == .centerY && constraint.secondAttribute == .centerY else { continue }
            let first = constraint.firstItem as? NSView
            let second = constraint.secondItem as? NSView
            if first === cell.icon {
                constraint.constant = iconOffset
                hasIconCenterY = true
            } else if second === cell.icon {
                constraint.constant = -iconOffset
                hasIconCenterY = true
            }
            if first === cell.label {
                constraint.constant = labelOffset
                hasLabelCenterY = true
            } else if second === cell.label {
                constraint.constant = -labelOffset
                hasLabelCenterY = true
            }
        }

        if !hasIconCenterY {
            NSLayoutConstraint.activate([
                cell.icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor, constant: iconOffset)
            ])
        }

        if !hasLabelCenterY {
            NSLayoutConstraint.activate([
                cell.label.centerYAnchor.constraint(equalTo: cell.centerYAnchor, constant: labelOffset)
            ])
        }
    }

    private func setupBasicCellAppearance(_ cell: SidebarCellView, baseFont: NSFont) {
        cell.icon.isHidden = false
        cell.icon.contentTintColor = nil
        cell.icon.imageScaling = .scaleProportionallyDown

        cell.label.lineBreakMode = .byTruncatingTail
        cell.label.cell?.truncatesLastVisibleLine = true
        cell.label.cell?.wraps = false
        if #available(macOS 10.14, *) {
            cell.label.maximumNumberOfLines = 1
        }

        cell.label.font = baseFont
        cell.label.textColor = Theme.textColor
    }

    private func updateIconLeading(_ cell: SidebarCellView, leading: CGFloat) {
        if let constraint = cell.constraints.first(where: {
            guard ($0.firstItem as? NSView) === cell.icon,
                $0.firstAttribute == .leading,
                ($0.secondItem as? NSView) === cell,
                $0.secondAttribute == .leading
            else {
                return false
            }
            return true
        }) {
            constraint.constant = leading
        } else {
            cell.icon.frame.origin.x = leading
        }

        cell.layoutSubtreeIfNeeded()
    }

    private func adjustIconSize(_ cell: SidebarCellView, size: CGFloat) {
        for constraint in cell.icon.constraints where constraint.firstAttribute == .width || constraint.firstAttribute == .height {
            constraint.constant = size
        }
        cell.icon.frame.size = NSSize(width: size, height: size)
        cell.layoutSubtreeIfNeeded()
    }

    private func updateLabelSpacing(_ cell: SidebarCellView, spacing: CGFloat) {
        cell.layoutSubtreeIfNeeded()
        let iconFrame = cell.icon.frame
        let desiredLeading = iconFrame.origin.x + iconFrame.size.width + spacing

        if let constraint = cell.constraints.first(where: {
            guard ($0.firstItem as? NSView) === cell.label,
                $0.firstAttribute == .leading,
                ($0.secondItem as? NSView) === cell,
                $0.secondAttribute == .leading
            else {
                return false
            }
            return true
        }) {
            constraint.constant = desiredLeading
        } else {
            cell.label.frame.origin.x = desiredLeading
        }

        cell.layoutSubtreeIfNeeded()
    }

    private func updateLabelVerticalNudge(_ cell: SidebarCellView, nudge: CGFloat) {
        if let labelCell = cell.label.cell as? SidebarLabelCell {
            labelCell.verticalNudge = nudge
            cell.label.needsDisplay = true
        }
    }

    private func configureForSidebarItemType(_ cell: SidebarCellView, sidebarItem: SidebarItem, baseFont: NSFont, accentColor: NSColor) {
        // The brand lockup (maintainer, 2026-10-11): an upright Charter
        // wordmark at regular weight, two points above the folder labels with a 22pt bird, in a
        // 52pt row so the space above and below it is even and wider than the
        // gap between folders. The italic wordmark with a slanted 26pt bird
        // leaned against the upright folder names and read too large; a
        // lockup of icon 20 and font +1 was rejected earlier as too small.
        let accentIconSize: CGFloat = 22
        let accentSpacing: CGFloat = 5
        let accentIconLeading: CGFloat = -2
        let accentFont = createAccentFont(from: baseFont)

        switch sidebarItem.type {
        case .Brand:
            cell.icon.image = NSImage(imageLiteralResourceName: "home")
            cell.icon.image?.isTemplate = true
            cell.icon.contentTintColor = accentColor
            updateIconLeading(cell, leading: accentIconLeading)
            adjustIconSize(cell, size: accentIconSize)
            cell.label.font = accentFont
            cell.label.textColor = accentColor
            updateLabelVerticalNudge(cell, nudge: Theme.Metrics.sidebarBrandLabelVerticalNudge)
            updateLabelSpacing(cell, spacing: accentSpacing)
            cell.label.lineBreakMode = .byTruncatingTail
            cell.label.cell?.truncatesLastVisibleLine = true
            // The bird icon has a different visual center from folder icons.
            for constraint in cell.constraints
            where constraint.firstAttribute == .centerY && constraint.secondAttribute == .centerY {
                let first = constraint.firstItem as? NSView
                let second = constraint.secondItem as? NSView
                if first === cell.icon {
                    constraint.constant = Theme.Metrics.sidebarBrandIconOffsetY
                    break
                } else if second === cell.icon {
                    constraint.constant = -Theme.Metrics.sidebarBrandIconOffsetY
                    break
                }
            }

        case .All:
            cell.icon.image = NSImage(imageLiteralResourceName: "allNotes")
            cell.icon.image?.isTemplate = true
            cell.icon.contentTintColor = Theme.sidebarActionColor

        case .Trash:
            cell.icon.image = NSImage(imageLiteralResourceName: "deleteNote")
            cell.icon.image?.isTemplate = true
            cell.icon.contentTintColor = Theme.sidebarActionColor

        case .Category:
            cell.icon.image = NSImage(imageLiteralResourceName: "project")
            cell.icon.image?.isTemplate = true
            cell.icon.contentTintColor = Theme.sidebarActionColor
        }
    }

    /// The wordmark face: Charter at regular weight, which ships with macOS,
    /// two points above the folder labels; the bold cut read heavy beside the
    /// folder names. The label face stands in if Charter is ever missing.
    private func createAccentFont(from baseFont: NSFont) -> NSFont {
        if let charter = NSFont(name: "Charter-Roman", size: baseFont.pointSize + 2) {
            return charter
        }
        return NSFont(descriptor: baseFont.fontDescriptor, size: baseFont.pointSize + 2) ?? baseFont
    }

    private func applyFinalStyling(_ cell: SidebarCellView, sidebarItem: SidebarItem, accentColor: NSColor) {
        cell.label.addCharacterSpacing()

        let color = sidebarItem.type == .Brand ? accentColor : Theme.textColor
        applyLabelColor(cell, color: color)
    }

    private func applyLabelColor(_ cell: SidebarCellView, color: NSColor) {
        let attributed = NSMutableAttributedString(attributedString: cell.label.attributedStringValue)
        let range = NSRange(location: 0, length: attributed.length)
        if range.length > 0 {
            attributed.addAttribute(.foregroundColor, value: color, range: range)
            cell.label.attributedStringValue = attributed
        } else {
            cell.label.textColor = color
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let sidebar = sidebarItems, item == nil {
            return sidebar.count
        }

        if let sidebarItem = item as? SidebarItem {
            if sidebarItem.children == nil {
                sidebarItem.children = getSubdirectories(for: sidebarItem)
            }
            return sidebarItem.children?.count ?? 0
        }

        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if let sidebarItem = item as? SidebarItem {
            if sidebarItem.type == .Brand {
                return UIConstants.brandRowHeight
            }
            return UIConstants.defaultRowHeight
        }
        return 24
    }

    // MARK: - Restoring the folder tree

    /// autosaveExpandedItems stores what this returns and asks for the item
    /// back at launch; without the pair the expanded state was never saved.
    func outlineView(_ outlineView: NSOutlineView, persistentObjectForItem item: Any?) -> Any? {
        guard let item = item as? SidebarItem, item.type == .Category else { return nil }
        return item.project?.url.path
    }

    func outlineView(_ outlineView: NSOutlineView, itemForPersistentObject object: Any) -> Any? {
        guard let path = object as? String else { return nil }
        return folderItem(forPath: path, expanding: false)
    }

    /// Expands the folders above `path` and returns the folder's row.
    func revealRow(forProjectPath path: String) -> Int? {
        guard let item = folderItem(forPath: path, expanding: true) else { return nil }
        let row = row(forItem: item)
        return row >= 0 ? row : nil
    }

    /// Walks down from the top-level folders to the one at `path`, creating
    /// children lazily as the data source does.
    private func folderItem(forPath path: String, expanding: Bool) -> SidebarItem? {
        var level = sidebarItems?.compactMap { $0 as? SidebarItem }.filter { $0.type == .Category } ?? []
        while true {
            let candidates = level.filter { item in
                guard let folder = item.project?.url.path else { return false }
                return path == folder || path.hasPrefix(folder + "/")
            }
            guard let next = candidates.max(by: { ($0.project?.url.path.count ?? 0) < ($1.project?.url.path.count ?? 0) }) else { return nil }
            if next.project?.url.path == path { return next }
            if next.children == nil { next.children = getSubdirectories(for: next) }
            if expanding { expandItem(next) }
            level = next.children ?? []
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let sidebarItem = item as? SidebarItem {
            if sidebarItem.type != .Category {
                return false
            }
            if sidebarItem.children == nil {
                sidebarItem.children = getSubdirectories(for: sidebarItem)
            }
            return (sidebarItem.children?.count ?? 0) > 0
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let sidebar = sidebarItems, item == nil {
            return sidebar[index]
        }

        if let sidebarItem = item as? SidebarItem {
            if sidebarItem.children == nil {
                sidebarItem.children = getSubdirectories(for: sidebarItem)
            }
            if let children = sidebarItem.children, index < children.count {
                return children[index]
            }
        }

        return ""
    }

    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        item
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cell = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "DataCell"), owner: self) as! SidebarCellView
        cell.endRenaming()

        guard let sidebarItem = item as? SidebarItem else {
            return cell
        }

        cell.textField?.stringValue = sidebarItem.name

        let baseFont = UserDefaultsManagement.nameFont ?? NSFont.systemFont(ofSize: 14)
        let accentColor = Theme.accentColor

        configureCellLayout(cell, baseFont: baseFont)
        configureForSidebarItemType(cell, sidebarItem: sidebarItem, baseFont: baseFont, accentColor: accentColor)
        applyFinalStyling(cell, sidebarItem: sidebarItem, accentColor: accentColor)

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

        // Check if allow dragging
        guard let sidebarItems = sidebarItems else { return nil }

        // Find the index in the root items list
        // We use identity matching since sidebar items are regenerated, but we need the index in the current `sidebarItems` array
        // Fallback to name/url matching if needed, but `sidebarItems` should contain the exact objects if not reloaded
        guard let itemIndex = sidebarItems.firstIndex(where: { ($0 as? SidebarItem) === sidebarItem }) else {
            // If strictly not equal, try matching by content to be safe
            guard
                let alternativeIndex = sidebarItems.firstIndex(where: {
                    guard let si = $0 as? SidebarItem else { return false }
                    return si.name == sidebarItem.name && si.project == sidebarItem.project
                })
            else {
                return nil
            }
            // If found by content value
            if alternativeIndex == 0 { return nil }
            let pasteboardItem = NSPasteboardItem()
            let encodedData = "SIDEBAR_REORDER:\(alternativeIndex):\(sidebarItem.name)"
            pasteboardItem.setString(encodedData, forType: .string)
            return pasteboardItem
        }

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
        guard let first = indexes.first else {
            return
        }
        // A row number saved before the brand row existed, or a removal that
        // falls back to the first row, lands on All Notes, not on the brand.
        if indexes.count == 1, let item = item(atRow: first) as? SidebarItem, !item.isSelectable() {
            guard let all = rowForSidebarSelection(type: .All, projectURL: nil, name: nil) else { return }
            super.selectRowIndexes([all], byExtendingSelection: extend)
            return
        }
        super.selectRowIndexes(indexes, byExtendingSelection: extend)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, let item = item(atRow: row) as? SidebarItem, !item.isSelectable() {
            return nil
        }
        return super.menu(for: event)
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

        guard sidebarItems != nil else {
            return
        }

        lastSelectedRow = selectedRow

        if let view = notification.object as? NSOutlineView {

            let i = view.selectedRow

            if let item = view.item(atRow: i) as? SidebarItem {
                // During app launch, skip saving selection to avoid overwriting persisted state
                // with programmatically restored selection. This ensures the correct last selection
                // is preserved across app restarts.
                if !isLaunch {
                    // Skip redundant updates if already on the same item
                    if UserDataService.instance.lastType == item.type.rawValue, UserDataService.instance.lastProject == item.project?.url,
                        UserDataService.instance.lastName == item.name
                    {
                        return
                    }

                    // Save user's manual selection for restoration on next launch
                    UserDefaultsManagement.lastProject = i
                    UserDefaultsManagement.lastProjectPath = item.type == .Category ? item.project?.url.path : nil
                }

                UserDataService.instance.lastType = item.type.rawValue
                UserDataService.instance.lastProject = item.project?.url
                UserDataService.instance.lastName = item.name
            } else {
            }

            // Don't clear edit area during launch to prevent flashing
            if !isLaunch {
                // Previously we called editArea.clear() here, which wiped the
                // editor body and titleBar to a blank frame for the entire
                // duration of updateTable + selection change (typically 100-
                // 300 ms). The fill() triggered by the new sidebar's first
                // note will replace content atomically, so leaving the prior
                // note visible until then yields a smoother crossfade with no
                // intermediate blank state. handleEmptyResults still clears
                // when the new sidebar item has zero notes.
                vd.search.stringValue = ""
                // Save current scroll position when switching projects
                vd.notesTableView.saveScrollPosition()
            }

            guard !UserDataService.instance.skipSidebarSelection else {
                UserDataService.instance.skipSidebarSelection = false
                return
            }

            var projects = [Project]()
            var targetItem: SidebarItem?

            for i in view.selectedRowIndexes {
                if let si = view.item(atRow: i) as? SidebarItem {
                    if let project = si.project {
                        projects.append(project)
                    }

                    if i == view.selectedRow {
                        targetItem = si
                    }
                }
            }

            if targetItem == nil {
                targetItem = getSidebarItem()
            }

            vd.updateTable(sidebarItem: targetItem, projects: projects.isEmpty ? nil : projects) {
                if self.isLaunch {
                    // During launch, restore note selection
                    if let url = UserDefaultsManagement.lastSelectedURL,
                        let lastNote = vd.storage.getBy(url: url),
                        let i = vd.notesTableView.getIndex(lastNote)
                    {
                        vd.notesTableView.selectRow(i, ensureVisible: false, suppressSideEffects: true)
                        vd.notesTableView.restoreScrollPosition(ensureSelectionVisible: false)
                    } else if !vd.notesTableView.noteList.isEmpty {
                        vd.notesTableView.restoreScrollPosition(ensureSelectionVisible: false)
                        vd.notesTableView.selectRow(0, ensureVisible: false)
                    }
                } else {
                    DispatchQueue.main.async {
                        // Keep note selection intact when single mode is active
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
    }

    @IBAction func renameMenu(_ sender: Any) {
        guard let vc = AppContext.shared.viewController, let v = vc.storageOutlineView else {
            return
        }

        let selected = v.selectedRow
        guard let sidebarItem = getSidebarItem(),
            sidebarItem.type == .Category,
            let projectRow = v.rowView(atRow: selected, makeIfNecessary: false),
            let cell = projectRow.view(atColumn: 0) as? SidebarCellView
        else {
            return
        }

        cell.label.isEditable = true
        cell.label.becomeFirstResponder()
    }

    @IBAction func moveFolderMenu(_ sender: Any) {
        guard let project = getSidebarItem()?.project, let window,
            !project.isRoot, !project.isDefault, !project.isTrash
        else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = project.getParent().url
        panel.prompt = I18n.str("Move")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let note = self.viewDelegate?.notesTableView.getSelectedNote()
                do {
                    try await self.storage.moveFolder(project, to: destination)
                    self.reloadSidebar()
                    if let row = self.revealRow(forProjectPath: project.url.path) {
                        self.selectRowIndexes([row], byExtendingSelection: false)
                    }
                    self.viewDelegate?.updateTable {
                        if let note { self.viewDelegate?.notesTableView.setSelected(note: note) }
                    }
                } catch {
                    AppDelegate.trackError(error, context: "SidebarProjectView.moveFolder")
                    MiaoYanAlert.show(message: I18n.str(error.localizedDescription), style: .warning, for: window)
                }
            }
        }
    }

    @IBAction func deleteMenu(_ sender: Any) {
        guard let vc = AppContext.shared.viewController, let v = vc.storageOutlineView else {
            return
        }

        guard let sidebarItem = getSidebarItem(), let project = sidebarItem.project, !project.isDefault, sidebarItem.type != .All, sidebarItem.type != .Trash else {
            return
        }

        if !project.isRoot, sidebarItem.type == .Category {
            guard let w = v.superview?.window else {
                return
            }

            MiaoYanAlert.confirm(
                message: String(format: I18n.str("Move the folder \u{201C}%@\u{201D} and everything in it to the Trash?"), project.label),
                confirmTitle: I18n.str("Move to Trash"),
                for: w
            ) { [weak vc, weak v] confirmed in
                guard let vc = vc, let v = v else { return }
                if confirmed {
                    guard let resultingItemUrl = self.storage.trashItem(url: project.url) else {
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
                        AppDelegate.trackError(error, context: "SidebarProjectView.removeProject.moveItem")
                    }
                }
            }
            return
        }
        v.removeProject(project: project)
    }

    @IBAction func addProject(_ sender: Any) {
        let project = storage.getMainProject()
        showAddFolderAlert(parentProject: project)
    }

    @IBAction func newSubfolder(_ sender: Any) {
        guard let sidebarItem = getSidebarItem(), let project = sidebarItem.project else { return }
        showAddFolderAlert(parentProject: project)
    }

    private func showAddFolderAlert(parentProject: Project) {
        guard let window = MainWindowController.shared() else {
            return
        }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        field.focusRingType = .none
        field.placeholderString = I18n.str("Project name")
        let alert = MiaoYanAlert.make(
            message: I18n.str("New project"),
            style: .informational,
            buttons: [I18n.str("Add"), I18n.str("Cancel")]
        )
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        MiaoYanAlert.softenTitle(of: alert)
        alert.beginSheetModal(for: window) { [weak self] (returnCode: NSApplication.ModalResponse) in
            if returnCode == NSApplication.ModalResponse.alertFirstButtonReturn {
                self?.addChild(field: field, project: parentProject)
            }
        }

        DispatchQueue.main.async {
            field.becomeFirstResponder()
        }
    }

    private func removeProject(project: Project) {
        storage.removeBy(project: project)

        viewDelegate?.fsManager?.restart()
        viewDelegate?.cleanSearchAndEditArea()

        reloadSidebar()
    }

    private func addChild(field: NSTextField, project: Project) {
        let value = field.stringValue
        guard !value.isEmpty else {
            return
        }

        do {
            let projectURL = project.url.appendingPathComponent(value, isDirectory: true)
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: false, attributes: nil)

            // Correct logic: we are creating a child of `project`.
            let actualNewProject = Project(url: projectURL, parent: project)

            _ = storage.add(project: actualNewProject)

            // Invalidate cache of the parent sidebar item so it re-fetches children
            if let sidebarItems = sidebarItems {
                // We need to find the sidebar item that corresponds to `project` and clear its children
                clearChildrenCache(for: project, in: sidebarItems)
            }

            reloadSidebar()

            // Auto expand the parent
            // We need to find the item to expand it. `reloadSidebar` rebuilds `sidebarItems`.
            // Expansion restoration might handle it if we saved state, but new item needs explicit expansion potentially.
            DispatchQueue.main.async {
                if AppContext.shared.viewController != nil {
                    // Try to find and expand
                    // Complex to find exact item after reload without tree traversal,
                    // but `reloadSidebar` maintains selection?
                    // Let's rely on user expanding for now, or existing auto-save.
                }
            }

        } catch {
            MiaoYanAlert.show(
                message: error.localizedDescription,
                style: .warning,
                for: window
            )
        }
    }

    private func addRoot() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = false
        openPanel.begin { [weak self] result in
            guard let self = self else { return }
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
        guard let vc = AppContext.shared.viewController, let v = vc.storageOutlineView else {
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

        if let root = storage.getRootProject() {
            return [root]
        }
        return nil
    }

    public func selectNext() {
        let i = selectedRow + 1
        if i < numberOfRows, let next = item(atRow: i) as? SidebarItem {
            if next.project == nil {
                let j = i + 1
                if j < numberOfRows, item(atRow: j) is SidebarItem {
                    selectRowIndexes([j], byExtendingSelection: false)
                    return
                }
                return
            }
            selectRowIndexes([i], byExtendingSelection: false)
        }
    }

    public func selectPrev() {
        let i = selectedRow - 1
        if i >= 0, let prev = item(atRow: i) as? SidebarItem {
            if prev.project == nil {
                let j = i - 1
                if j >= 0, item(atRow: j) is SidebarItem {
                    selectRowIndexes([j], byExtendingSelection: false)
                    return
                }
                return
            }
            selectRowIndexes([i], byExtendingSelection: false)
        }
    }

    private func getSidebarItem() -> SidebarItem? {
        // When called on a proxy (Application Scene customObject, not in any window),
        // delegate to the actual SidebarProjectView in the window via AppContext.
        let target: SidebarProjectView
        if window != nil {
            target = self
        } else if let actual = AppContext.shared.viewController?.storageOutlineView as? SidebarProjectView {
            target = actual
        } else {
            return nil
        }
        let row = target.selectedRow
        if row < 0 { return nil }
        return target.item(atRow: row) as? SidebarItem
    }

    private func rowForSidebarSelection(type: SidebarItemType, projectURL: URL?, name: String?) -> Int? {
        for row in 0..<numberOfRows {
            guard let item = item(atRow: row) as? SidebarItem else {
                continue
            }

            guard item.type == type else {
                continue
            }

            switch type {
            case .Brand:
                return nil
            case .All:
                return row
            case .Category, .Trash:
                if item.project?.url == projectURL {
                    return row
                }
            }
        }

        return nil
    }

    @objc public func reloadSidebar() {
        guard let vc = AppContext.shared.viewController else {
            return
        }
        vc.fsManager?.restart()
        vc.loadMoveMenu()

        let selectedRow = vc.storageOutlineView.selectedRow
        let selectedItem = vc.storageOutlineView.item(atRow: selectedRow) as? SidebarItem

        // Save expanded state before reload
        let expandedState = vc.storageOutlineView.saveExpandedState()

        let newList = Sidebar().getList()
        var mergedList = [Any]()

        // Smarter merge: Reuse existing SidebarItem objects to preserve expanded state/identity
        if let currentItems = vc.storageOutlineView.sidebarItems {
            for newItem in newList {
                if let newSidebarItem = newItem as? SidebarItem {
                    if let existingItem = currentItems.first(where: {
                        if let si = $0 as? SidebarItem {
                            return si.isSame(as: newSidebarItem)
                        }
                        return false
                    }) as? SidebarItem {
                        // Reuse existing object and clear its children cache
                        existingItem.name = newSidebarItem.name
                        existingItem.project = newSidebarItem.project
                        existingItem.type = newSidebarItem.type
                        existingItem.icon = newSidebarItem.icon
                        existingItem.children = nil
                        mergedList.append(existingItem)
                    } else {
                        mergedList.append(newSidebarItem)
                    }
                } else {
                    mergedList.append(newItem)
                }
            }
        } else {
            mergedList = newList
        }

        vc.storageOutlineView.sidebarItems = mergedList
        vc.storageOutlineView.reloadData()

        // Restore expanded state after reload
        vc.storageOutlineView.restoreExpandedState(expandedState)

        let restoredRow =
            vc.storageOutlineView.rowForSidebarSelection(
                type: selectedItem?.type ?? .All,
                projectURL: selectedItem?.project?.url,
                name: selectedItem?.name
            )
            ?? (vc.storageOutlineView.numberOfRows > selectedRow && selectedRow >= 0 ? selectedRow : nil)
            ?? vc.storageOutlineView.rowForSidebarSelection(type: .All, projectURL: nil, name: nil)

        if let restoredRow {
            vc.storageOutlineView.selectRowIndexes([restoredRow], byExtendingSelection: false)
        }
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
    private func getSubdirectories(for sidebarItem: SidebarItem) -> [SidebarItem] {
        guard let project = sidebarItem.project, sidebarItem.type == .Category else { return [] }
        let icon = NSImage(imageLiteralResourceName: "project")
        return storage.subfolders(of: project).map {
            SidebarItem(name: $0.label, project: $0, type: .Category, icon: icon)
        }
    }

    private func clearChildrenCache(for targetProject: Project, in items: [Any]) {
        for item in items {
            if let sidebarItem = item as? SidebarItem {
                if sidebarItem.project == targetProject {
                    sidebarItem.children = nil
                    return
                }
                if let children = sidebarItem.children {
                    clearChildrenCache(for: targetProject, in: children)
                }
            }
        }
    }

    private func saveExpandedState() -> Set<String> {
        var expandedPaths = Set<String>()

        for row in 0..<numberOfRows {
            if let item = item(atRow: row) as? SidebarItem,
                isItemExpanded(item),
                let project = item.project
            {
                expandedPaths.insert(project.url.path)
            }
        }

        return expandedPaths
    }

    private func restoreExpandedState(_ expandedPaths: Set<String>) {
        func expandRecursively(item: Any?) {
            let childCount = numberOfChildren(ofItem: item)
            for i in 0..<childCount {
                let child = self.child(i, ofItem: item)
                if let sidebarItem = child as? SidebarItem,
                    let project = sidebarItem.project,
                    expandedPaths.contains(project.url.path)
                {
                    expandItem(sidebarItem)
                    // Recursively expand children
                    expandRecursively(item: sidebarItem)
                }
            }
        }

        expandRecursively(item: nil)
    }

    private func clearAllChildrenCache(items: [Any]) {
        for item in items {
            if let sidebarItem = item as? SidebarItem {
                let children = sidebarItem.children
                sidebarItem.children = nil
                if let children = children {
                    clearAllChildrenCache(items: children)
                }
            }
        }
    }
}
