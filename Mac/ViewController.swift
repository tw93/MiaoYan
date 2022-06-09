import Cocoa
import LocalAuthentication
import MASShortcut
import MiaoYanCore_macOS
import WebKit

class ViewController: NSViewController,
    NSTextViewDelegate,
    NSTextFieldDelegate,
    NSSplitViewDelegate,
    NSOutlineViewDelegate,
    NSOutlineViewDataSource,
    WebFrameLoadDelegate,
    NSMenuItemValidation
{
    // MARK: - Properties

    public var fsManager: FileSystemEventManager?
    private var projectSettingsViewController: ProjectSettingsViewController?

    let storage = Storage.sharedInstance()
    var filteredNoteList: [Note]?
    var alert: NSAlert?
    var refilled: Bool = false
    var timer = Timer()
    var sidebarTimer = Timer()
    var rowUpdaterTimer = Timer()
    let searchQueue = OperationQueue()

    private var updateViews = [Note]()

    override var representedObject: Any? {
        didSet {} // Update the view, if already loaded.
    }

    // MARK: - IBOutlets

    @IBOutlet var emptyEditAreaImage: NSImageView!
    @IBOutlet var emptyEditAreaView: NSView!
    @IBOutlet var splitView: EditorSplitView!
    @IBOutlet var editArea: EditTextView!
    @IBOutlet var editAreaScroll: EditorScrollView!
    @IBOutlet var search: SearchTextField!
    @IBOutlet var notesTableView: NotesTableView!
    @IBOutlet var noteMenu: NSMenu!
    @IBOutlet var storageOutlineView: SidebarProjectView!
    @IBOutlet var sidebarSplitView: NSSplitView!
    @IBOutlet var notesListCustomView: NSView!
    @IBOutlet var outlineHeader: OutlineHeaderView!

    @IBOutlet var searchTopConstraint: NSLayoutConstraint!
    @IBOutlet var titleLabel: TitleTextField! {
        didSet {
            titleLabel.layer?.masksToBounds = false
        }
    }

    @IBOutlet var sortByOutlet: NSMenuItem!
    @IBOutlet var titleBarAdditionalView: NSVisualEffectView! {
        didSet {
            let layer = CALayer()
            layer.frame = titleBarAdditionalView.bounds
            layer.backgroundColor = .clear
            titleBarAdditionalView.wantsLayer = true
            titleBarAdditionalView.layer = layer
        }
    }

    @IBOutlet var previewButton: NSButton! {
        didSet {
            previewButton.state = UserDefaultsManagement.preview ? .on : .off
        }
    }

    @IBOutlet var titleBarView: TitleBarView!
    @IBOutlet var sidebarScrollView: NSScrollView!
    @IBOutlet var notesScrollView: NSScrollView!

    // MARK: - Overrides

    override func viewDidLoad() {
        configureShortcuts()
        configureDelegates()
        configureLayout()
        configureNotesList()
        configureEditor()

        fsManager = FileSystemEventManager(storage: storage, delegate: self)
        fsManager?.start()

        loadMoveMenu()
        loadSortBySetting()
        checkSidebarConstraint()

        #if CLOUDKIT
            registerKeyValueObserver()
        #endif

        searchQueue.maxConcurrentOperationCount = 1

        notesTableView.loadingQueue.maxConcurrentOperationCount = 1
        notesTableView.loadingQueue.qualityOfService = QualityOfService.userInteractive
    }

    override func viewDidAppear() {
        if UserDefaultsManagement.fullScreen {
            view.window?.toggleFullScreen(nil)
        }

        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            if let urls = appDelegate.urls {
                appDelegate.importNotes(urls: urls)
                return
            }

            if let query = appDelegate.searchQuery {
                appDelegate.search(query: query)
                return
            }

            if appDelegate.newName != nil || appDelegate.newContent != nil {
                let name = appDelegate.newName ?? ""
                let content = appDelegate.newContent ?? ""

                appDelegate.create(name: name, content: content)
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let vc = ViewController.shared() else { return false }

        if let title = menuItem.menu?.identifier?.rawValue {
            switch title {
            case "miaoyanMenu":
                if menuItem.identifier?.rawValue == "emptyTrashMenu" {
                    menuItem.keyEquivalentModifierMask = [.command, .option, .shift]
                    return true
                }
            case "fileMenu":
                if menuItem.identifier?.rawValue == "fileMenu.delete" {
                    menuItem.keyEquivalentModifierMask = [.command]
                }

                if ["fileMenu.new", "fileMenu.searchAndCreate", "fileMenu.import"].contains(menuItem.identifier?.rawValue) {
                    return true
                }

                if vc.notesTableView.selectedRow == -1 {
                    return false
                }

            case "folderMenu":
                if ["folderMenu.attachStorage"].contains(menuItem.identifier?.rawValue) {
                    return true
                }

                guard let p = vc.getSidebarProject(), !p.isTrash else {
                    return false
                }
            case "findMenu":
                if ["findMenu.find", "findMenu.findAndReplace", "findMenu.next", "findMenu.prev"].contains(menuItem.identifier?.rawValue), vc.notesTableView.selectedRow > -1 {
                    return true
                }

                return vc.editAreaScroll.isFindBarVisible || vc.editArea.hasFocus()
            default:
                break
            }
        }

        return true
    }

    // MARK: - Initial configuration

    private func configureLayout() {
        updateTitle(newTitle: "")

        DispatchQueue.main.async {
            self.editArea.updateTextContainerInset()
        }

        editArea.textContainerInset.height = 10
        editArea.isEditable = false

        editArea.layoutManager?.defaultAttachmentScaling = .scaleProportionallyDown

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(UserDefaultsManagement.editorLineSpacing)
        editArea.defaultParagraphStyle = paragraphStyle
        editArea.typingAttributes[.paragraphStyle] = paragraphStyle

        editArea.font = UserDefaultsManagement.noteFont

        setTableRowHeight()
        storageOutlineView.sidebarItems = Sidebar().getList()

        storageOutlineView.selectionHighlightStyle = .regular

        sidebarSplitView.autosaveName = "SidebarSplitView"
        splitView.autosaveName = "EditorSplitView"

        notesScrollView.scrollerStyle = .overlay
        sidebarScrollView.scrollerStyle = .overlay
    }

    private func configureNotesList() {
        updateTable {
            let lastSidebarItem = UserDefaultsManagement.lastProject
            if let items = self.storageOutlineView.sidebarItems, items.indices.contains(lastSidebarItem) {
                DispatchQueue.main.async {
                    self.storageOutlineView.selectRowIndexes([lastSidebarItem], byExtendingSelection: false)
                }
            }
        }
    }

    private func configureEditor() {
        editArea.usesFindBar = false
        editArea.isIncrementalSearchingEnabled = true
        editArea.isAutomaticLinkDetectionEnabled = false
        editArea.isAutomaticQuoteSubstitutionEnabled = false
        editArea.isAutomaticDataDetectionEnabled = false
        editArea.isAutomaticTextReplacementEnabled = false
        editArea.textStorage?.delegate = editArea.textStorage
        editArea.viewDelegate = self
    }

    private func configureShortcuts() {
        MASShortcutMonitor.shared().register(UserDefaultsManagement.newNoteShortcut, withAction: {
            self.makeNoteShortcut()
        })

        MASShortcutMonitor.shared().register(UserDefaultsManagement.searchNoteShortcut, withAction: {
            self.searchShortcut()
        })

        NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.flagsChanged) {
            $0
        }

        NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.keyDown) {
            if self.keyDown(with: $0) {
                return $0
            }
            return nil
        }
    }

    private func configureDelegates() {
        editArea.delegate = self
        search.vcDelegate = self
        search.delegate = search
        sidebarSplitView.delegate = self
        storageOutlineView.viewDelegate = self
    }

    // MARK: - Actions

    @IBAction func searchAndCreate(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }

        let size = vc.splitView.subviews[0].frame.width

        if size == 0 {
            toggleNoteList(self)
        }

        vc.search.window?.makeFirstResponder(vc.search)
    }

    @IBAction func sortBy(_ sender: NSMenuItem) {
        if let id = sender.identifier {
            let key = String(id.rawValue.dropFirst(3))
            guard let sortBy = SortBy(rawValue: key) else { return }

            UserDefaultsManagement.sort = sortBy
            UserDefaultsManagement.sortDirection = !UserDefaultsManagement.sortDirection

            if let submenu = sortByOutlet.submenu {
                for item in submenu.items {
                    item.state = NSControl.StateValue.off
                }
            }

            sender.state = NSControl.StateValue.on

            guard let controller = ViewController.shared() else { return }

            // Sort all notes
            storage.noteList = storage.sortNotes(noteList: storage.noteList, filter: controller.search.stringValue)

            // Sort notes in the current project
            if let filtered = controller.filteredNoteList {
                controller.notesTableView.noteList = storage.sortNotes(noteList: filtered, filter: controller.search.stringValue)
            } else {
                controller.notesTableView.noteList = storage.noteList
            }

            controller.notesTableView.reloadData()
        }
    }

    @objc func moveNote(_ sender: NSMenuItem) {
        let project = sender.representedObject as! Project

        guard let notes = notesTableView.getSelectedNotes() else {
            return
        }

        move(notes: notes, project: project)
    }

    public func move(notes: [Note], project: Project) {
        for note in notes {
            if note.project == project {
                continue
            }

            let destination = project.url.appendingPathComponent(note.name)

            if note.type == .Markdown, note.container == .none {
                let imagesMeta = note.getAllImages()
                for imageMeta in imagesMeta {
                    move(note: note, from: imageMeta.url, imagePath: imageMeta.path, to: project)
                }

                if imagesMeta.count > 0 {
                    note.save()
                }
            }

            _ = note.move(to: destination, project: project)

            note.invalidateCache()
        }

        editArea.clear()
    }

    private func move(note: Note, from imageURL: URL, imagePath: String, to project: Project, copy: Bool = false) {
        let dstPrefix = NotesTextProcessor.getAttachPrefix(url: imageURL)
        let dest = project.url.appendingPathComponent(dstPrefix)

        if !FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false, attributes: nil)
        }

        do {
            if copy {
                try FileManager.default.copyItem(at: imageURL, to: dest)
            } else {
                try FileManager.default.moveItem(at: imageURL, to: dest)
            }
        } catch {
            if let fileName = ImagesProcessor.getFileName(from: imageURL, to: dest, ext: imageURL.pathExtension) {
                let dest = dest.appendingPathComponent(fileName)

                if copy {
                    try? FileManager.default.copyItem(at: imageURL, to: dest)
                } else {
                    try? FileManager.default.moveItem(at: imageURL, to: dest)
                }

                let prefix = "]("
                let postfix = ")"

                let find = prefix + imagePath + postfix
                let replace = prefix + dstPrefix + fileName + postfix

                guard find != replace else { return }

                while note.content.mutableString.contains(find) {
                    let range = note.content.mutableString.range(of: find)
                    note.content.replaceCharacters(in: range, with: replace)
                }
            }
        }
    }

    func viewDidResize() {
        guard let vc = ViewController.shared() else { return }
        vc.checkSidebarConstraint()

        if !refilled {
            refilled = true
            DispatchQueue.main.async {
                self.refillEditArea(previewOnly: true)
                self.refilled = false
            }
        }
    }

    func reloadSideBar() {
        guard let outline = storageOutlineView else { return }

        sidebarTimer.invalidate()
        sidebarTimer = Timer.scheduledTimer(timeInterval: 1.2, target: outline, selector: #selector(outline.reloadSidebar), userInfo: nil, repeats: false)
    }

    func reloadView(note: Note? = nil) {
        let notesTable = notesTableView!
        let selectedNote = notesTable.getSelectedNote()
        let cursor = editArea.selectedRanges[0].rangeValue.location

        updateTable {
            if let selected = selectedNote, let index = notesTable.getIndex(selected) {
                notesTable.selectRowIndexes([index], byExtendingSelection: false)
                self.refillEditArea(cursor: cursor)
            }
        }
    }

    func setTableRowHeight() {
        notesTableView.rowHeight = CGFloat(52)
        notesTableView.reloadData()
    }

    func refillEditArea(cursor: Int? = nil, previewOnly: Bool = false, saveTyping: Bool = false, force: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            self?.previewButton.state = UserDefaultsManagement.preview ? .on : .off
        }

        guard !previewOnly || previewOnly && UserDefaultsManagement.preview else {
            return
        }

        DispatchQueue.main.async {
            var location: Int = 0

            if let unwrappedCursor = cursor {
                location = unwrappedCursor
            } else {
                location = self.editArea.selectedRanges[0].rangeValue.location
            }

            let selected = self.notesTableView.selectedRow
            if selected > -1, self.notesTableView.noteList.indices.contains(selected) {
                if let note = self.notesTableView.getSelectedNote() {
                    self.editArea.fill(note: note, saveTyping: saveTyping, force: force)
                    self.editArea.setSelectedRange(NSRange(location: location, length: 0))
                }
            }
        }
    }

    public func keyDown(with event: NSEvent) -> Bool {
        guard let mw = MainWindowController.shared() else { return false }

        guard alert == nil else {
            if event.keyCode == kVK_Escape, let unwrapped = alert {
                mw.endSheet(unwrapped.window)
                alert = nil
            }

            return true
        }

        if event.keyCode == kVK_Delete, event.modifierFlags.contains(.command), search.hasFocus() {
            search.stringValue.removeAll()
            return false
        }

        if event.keyCode == kVK_Delete, event.modifierFlags.contains(.command), editArea.hasFocus() {
            editArea.deleteToBeginningOfLine(nil)
            return false
        }

        if event.keyCode == kVK_Delete, event.modifierFlags.contains(.command), titleLabel.hasFocus() {
            updateTitle(newTitle: "")
            return false
        }

        // Return / Cmd + Return navigation
        if event.keyCode == kVK_Return {
            if let fr = NSApp.mainWindow?.firstResponder, alert == nil {
                if event.modifierFlags.contains(.command) {
                    if fr.isKind(of: NotesTableView.self) {
                        NSApp.mainWindow?.makeFirstResponder(storageOutlineView)
                        return false
                    }

                    if fr.isKind(of: EditTextView.self) {
                        NSApp.mainWindow?.makeFirstResponder(notesTableView)
                        return false
                    }
                } else {
                    if fr.isKind(of: SidebarProjectView.self) {
                        notesTableView.selectNext()
                        NSApp.mainWindow?.makeFirstResponder(notesTableView)
                        return false
                    }

                    if let note = EditTextView.note, fr.isKind(of: NotesTableView.self), !(UserDefaultsManagement.preview && !note.isRTF()) {
                        NSApp.mainWindow?.makeFirstResponder(editArea)
                        return false
                    }
                }
            }

            return true
        }

        // Tab / Control + Tab
        if event.keyCode == kVK_Tab {
            if event.modifierFlags.contains(.control) {
                notesTableView.window?.makeFirstResponder(notesTableView)
                return true
            }

            if let fr = NSApp.mainWindow?.firstResponder, fr.isKind(of: NotesTableView.self) {
                NSApp.mainWindow?.makeFirstResponder(notesTableView)
                return false
            }
        }

        // Focus search bar on ESC
        if

            event.keyCode == kVK_Escape
            || (
                event.characters == "." &&
                    event.modifierFlags.contains(.command)
            ),

            NSApplication.shared.mainWindow == NSApplication.shared.keyWindow
        {
            UserDataService.instance.resetLastSidebar()

            if let view = NSApplication.shared.mainWindow?.firstResponder as? NSTextView, let textField = view.superview?.superview, textField.isKind(of: NameTextField.self) {
                NSApp.mainWindow?.makeFirstResponder(notesTableView)
                return false
            }

            if editAreaScroll.isFindBarVisible {
                cancelTextSearch()
                return false
            }

            // Renaming is in progress
            if titleLabel.isEditable {
                titleLabel.window?.makeFirstResponder(notesTableView)
                return false
            }

            UserDefaultsManagement.lastProject = 0
            UserDefaultsManagement.lastSelectedURL = nil

            notesTableView.scroll(.zero)

            let hasSelectedNotes = notesTableView.selectedRow > -1
            let hasSelectedBarItem = storageOutlineView.selectedRow > -1

            if hasSelectedBarItem, hasSelectedNotes {
                UserDefaultsManagement.lastProject = 0
                UserDataService.instance.isNotesTableEscape = true
                notesTableView.deselectAll(nil)
                NSApp.mainWindow?.makeFirstResponder(search)
                return false
            }

            storageOutlineView.deselectAll(nil)
            cleanSearchAndEditArea()

            return true
        }

        // Search cmd-f
        if event.keyCode == kVK_ANSI_F, event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control) {
            if notesTableView.getSelectedNote() != nil {
                disablePreview()
                return true
            }
        }

        // Pin note shortcut (cmd+shift+p)
        if event.keyCode == kVK_ANSI_P, event.modifierFlags.contains(.shift), event.modifierFlags.contains(.command) {
            pin(notesTableView.selectedRowIndexes)
            return true
        }

        // 展开 sidebar cmd+1
        if event.modifierFlags.contains(.command), event.keyCode == kVK_ANSI_1 {
            toggleSidebar("")
            return false
        }

        // 保存
        if event.modifierFlags.contains(.command), event.keyCode == kVK_ANSI_S {
            titleLabel.saveTitle()
            return false
        }

        if let fr = mw.firstResponder, !fr.isKind(of: EditTextView.self), !fr.isKind(of: NSTextView.self), !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.control)
        {
            if let char = event.characters {
                let newSet = CharacterSet(charactersIn: char)
                if newSet.isSubset(of: CharacterSet.alphanumerics) {
                    search.becomeFirstResponder()
                }
            }
        }

        return true
    }

    func cancelTextSearch() {
        let menu = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.tag = NSTextFinder.Action.hideFindInterface.rawValue
        editArea.performTextFinderAction(menu)

        if !UserDefaultsManagement.preview {
            NSApp.mainWindow?.makeFirstResponder(editArea)
        }
    }

    @IBAction func makeNote(_ sender: SearchTextField) {
        guard let vc = ViewController.shared() else { return }

        if let type = vc.getSidebarType(), type == .Trash {
            vc.storageOutlineView.deselectAll(nil)
        }

        let value = sender.stringValue

        if value.count > 0 {
            search.stringValue = String()
            editArea.clear()
            createNote(name: value, content: "")
        } else {
            createNote(content: "")
        }
    }

    @IBAction func fileMenuNewNote(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }

        if let type = vc.getSidebarType(), type == .Trash {
            vc.storageOutlineView.deselectAll(nil)
        }
        if UserDefaultsManagement.defaultLanguage == 0 {
            vc.createNote(name: "未命名", content: "")
        } else {
            vc.createNote(name: "Untitled", content: "")
        }
    }

    @IBAction func importNote(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.begin { result in
            if result.rawValue == NSFileHandlingPanelOKButton {
                let urls = panel.urls
                let project = self.getSidebarProject() ?? self.storage.getMainProject()

                for url in urls {
                    _ = self.copy(project: project, url: url)
                }
            }
        }
    }

    @IBAction func moveMenu(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }

        if vc.notesTableView.selectedRow >= 0 {
            vc.loadMoveMenu()

            let moveTitle = NSLocalizedString("Move", comment: "Menu")
            let moveMenu = vc.noteMenu.item(withTitle: moveTitle)
            let view = vc.notesTableView.rect(ofRow: vc.notesTableView.selectedRow)
            let x = vc.splitView.subviews[0].frame.width + 5
            let general = moveMenu?.submenu?.item(at: 0)

            moveMenu?.submenu?.popUp(positioning: general, at: NSPoint(x: x, y: view.origin.y + 8), in: vc.notesTableView)
        }
    }

    @IBAction func fileName(_ sender: NSTextField) {
        guard let note = notesTableView.getNoteFromSelectedRow() else { return }

        let value = sender.stringValue
        let url = note.url

        let newName = sender.stringValue + "." + note.url.pathExtension
        let isSoftRename = note.url.lastPathComponent.lowercased() == newName.lowercased()

        if note.project.fileExist(fileName: value, ext: note.url.pathExtension), !isSoftRename {
            self.alert = NSAlert()
            guard let alert = alert else { return }

            alert.messageText = "Hmm, something goes wrong 🙈"
            alert.informativeText = "Note with name \"\(value)\" already exists in selected storage."
            alert.runModal()

            note.parseURL()
            sender.stringValue = note.getTitleWithoutLabel()
            return
        }

        guard value.count > 0 else {
            sender.stringValue = note.getTitleWithoutLabel()
            return
        }

        sender.isEditable = false

        let newUrl = note.getNewURL(name: value)
        UserDataService.instance.focusOnImport = newUrl

        if note.url.path == newUrl.path {
            return
        }

        note.overwrite(url: newUrl)

        do {
            try FileManager.default.moveItem(at: url, to: newUrl)
            print("File moved from \"\(url.deletingPathExtension().lastPathComponent)\" to \"\(newUrl.deletingPathExtension().lastPathComponent)\"")
        } catch {
            note.overwrite(url: url)
        }
    }

    @IBAction func finderMenu(_ sender: NSMenuItem) {
        if let notes = notesTableView.getSelectedNotes() {
            var urls = [URL]()
            for note in notes {
                urls.append(note.url)
            }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    @IBAction func makeMenu(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }

        if let type = vc.getSidebarType(), type == .Trash {
            vc.storageOutlineView.deselectAll(nil)
        }

        vc.createNote()
    }

    @IBAction func pinMenu(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        vc.pin(vc.notesTableView.selectedRowIndexes)
    }

    @IBAction func renameMenu(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        vc.titleLabel.restoreResponder = vc.view.window?.firstResponder

        switchTitleToEditMode()
    }

    @objc func switchTitleToEditMode() {
        guard let vc = ViewController.shared() else { return }

        vc.titleLabel.editModeOn()

        if let note = EditTextView.note {
            vc.titleLabel.stringValue = note.getShortTitle()
        }
    }

    @IBAction func deleteNote(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        guard let notes = vc.notesTableView.getSelectedNotes() else {
            return
        }

        if let si = vc.getSidebarItem(), si.isTrash() {
            removeForever()
            return
        }

        let selectedRow = vc.notesTableView.selectedRowIndexes.min()

        UserDataService.instance.searchTrigger = true

        vc.notesTableView.removeByNotes(notes: notes)

        vc.storage.removeNotes(notes: notes) { urls in

            if let appd = NSApplication.shared.delegate as? AppDelegate,
               let md = appd.mainWindowController
            {
                let undoManager = md.notesListUndoManager

                if let ntv = vc.notesTableView {
                    undoManager.registerUndo(withTarget: ntv, selector: #selector(ntv.unDelete), object: urls)
                    undoManager.setActionName(NSLocalizedString("Delete", comment: ""))
                }

                if let i = selectedRow, i > -1 {
                    vc.notesTableView.selectRow(i)
                }

                UserDataService.instance.searchTrigger = false
            }

            if UserDefaultsManagement.preview {
                vc.disablePreview()
            }

            vc.editArea.clear()
        }

        NSApp.mainWindow?.makeFirstResponder(vc.notesTableView)
    }

    @IBAction func toggleNoteList(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }

        let size = vc.splitView.subviews[0].frame.width

        if size == 0 {
            var size = UserDefaultsManagement.sidebarSize
            if UserDefaultsManagement.sidebarSize == 0 {
                size = 250
            }
            vc.splitView.shouldHideDivider = false
            vc.splitView.setPosition(size, ofDividerAt: 0)
        } else if vc.splitView.shouldHideDivider {
            vc.splitView.shouldHideDivider = false
            vc.splitView.setPosition(UserDefaultsManagement.sidebarSize, ofDividerAt: 0)
        } else {
            UserDefaultsManagement.sidebarSize = size

            vc.splitView.shouldHideDivider = true
            vc.splitView.setPosition(0, ofDividerAt: 0)
            DispatchQueue.main.async {
                vc.splitView.setPosition(0, ofDividerAt: 0)
            }
            // 防止空出现
            hideSidebar("")
        }
        vc.editArea.updateTextContainerInset()
    }

    @IBAction func toggleSidebar(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }

        let size = Int(vc.sidebarSplitView.subviews[0].frame.width)

        if size != 0 {
            UserDefaultsManagement.realSidebarSize = size
            vc.sidebarSplitView.setPosition(0, ofDividerAt: 0)
        } else {
            showNoteList("")
            vc.sidebarSplitView.setPosition(CGFloat(UserDefaultsManagement.realSidebarSize), ofDividerAt: 0)
        }

        vc.editArea.updateTextContainerInset()
    }

    func hideSidebar(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }

        let size = Int(vc.sidebarSplitView.subviews[0].frame.width)

        if size != 0 {
            UserDefaultsManagement.realSidebarSize = size
            vc.sidebarSplitView.setPosition(0, ofDividerAt: 0)
        }
        vc.editArea.updateTextContainerInset()
    }

    func showNoteList(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }

        let size = vc.splitView.subviews[0].frame.width

        if size == 0 {
            var size = UserDefaultsManagement.sidebarSize
            if UserDefaultsManagement.sidebarSize == 0 {
                size = 250
            }
            vc.splitView.shouldHideDivider = false
            vc.splitView.setPosition(size, ofDividerAt: 0)
        }
        vc.editArea.updateTextContainerInset()
    }

    @IBAction func emptyTrash(_ sender: NSMenuItem) {
        guard let vc = ViewController.shared() else { return }

        if let sidebarItem = vc.getSidebarItem(), sidebarItem.isTrash() {
            let indexSet = IndexSet(integersIn: 0 ..< vc.notesTableView.noteList.count)
            vc.notesTableView.removeRows(at: indexSet, withAnimation: .effectFade)
        }

        let notes = storage.getAllTrash()
        for note in notes {
            _ = note.removeFile()
        }

        NSSound(named: "Pop")?.play()
    }

    @IBAction func openProjectViewSettings(_ sender: NSMenuItem) {
        guard let vc = ViewController.shared() else {
            return
        }

        if let controller = vc.storyboard?.instantiateController(withIdentifier: "ProjectSettingsViewController")
            as? ProjectSettingsViewController
        {
            projectSettingsViewController = controller

            if let project = vc.getSidebarProject() {
                vc.presentAsSheet(controller)
                controller.load(project: project)
            }
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField, textField == titleLabel else { return }

        if titleLabel.isEditable == true {
            fileName(titleLabel)
            view.window?.makeFirstResponder(notesTableView)
        } else {
            let currentNote = notesTableView.getSelectedNote()
            updateTitle(newTitle: currentNote?.getTitleWithoutLabel() ?? NSLocalizedString("Untitled Note", comment: "Untitled Note"))
        }
    }

    public func blockFSUpdates() {
        timer.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(enableFSUpdates), userInfo: nil, repeats: false)

        UserDataService.instance.fsUpdatesDisabled = true
    }

    // Changed main edit view
    func textDidChange(_ notification: Notification) {
        guard let note = getCurrentNote() else { return }

        blockFSUpdates()

        if editArea.isEditable {
            editArea.removeHighlight()
            editArea.saveImages()

            note.save(attributed: editArea.attributedString())

            if !updateViews.contains(note) {
                updateViews.append(note)
            }

            rowUpdaterTimer.invalidate()
            rowUpdaterTimer = Timer.scheduledTimer(timeInterval: 1.2, target: self, selector: #selector(updateTableViews), userInfo: nil, repeats: false)
        }
    }

    public func getCurrentNote() -> Note? {
        EditTextView.note
    }

    private func removeForever() {
        guard let vc = ViewController.shared() else { return }
        guard let notes = vc.notesTableView.getSelectedNotes() else { return }
        guard let window = MainWindowController.shared() else { return }

        vc.alert = NSAlert()

        guard let alert = vc.alert else { return }

        alert.messageText = String(format: NSLocalizedString("Are you sure you want to irretrievably delete %d note(s)?", comment: ""), notes.count)

        alert.informativeText = NSLocalizedString("This action cannot be undone.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Remove note(s)", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.beginSheetModal(for: window) { (returnCode: NSApplication.ModalResponse) in
            if returnCode == NSApplication.ModalResponse.alertFirstButtonReturn {
                let selectedRow = vc.notesTableView.selectedRowIndexes.min()
                vc.editArea.clear()
                vc.storage.removeNotes(notes: notes) { _ in
                    DispatchQueue.main.async {
                        vc.storageOutlineView.reloadSidebar()
                        vc.notesTableView.removeByNotes(notes: notes)
                        if let i = selectedRow, i > -1 {
                            vc.notesTableView.selectRow(i)
                        }
                    }
                }
            } else {
                self.alert = nil
            }
        }
    }

    @objc func enableFSUpdates() {
        UserDataService.instance.fsUpdatesDisabled = false
    }

    @objc private func updateTableViews() {
        notesTableView.beginUpdates()
        for note in updateViews {
            notesTableView.reloadRow(note: note)

            if UserDefaultsManagement.sort == .modificationDate, UserDefaultsManagement.sortDirection == true {
                if let index = notesTableView.noteList.firstIndex(of: note) {
                    moveNoteToTop(note: index)
                }
            } else {
                sortAndMove(note: note)
            }
        }

        updateViews.removeAll()
        notesTableView.endUpdates()
    }

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

    private var selectRowTimer = Timer()

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
        if type == nil,
           projects == nil || (
               projects!.count < 2 && projects!.first!.isRoot
           )
        {
            type = .All
        }

        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self] in
            guard let self = self else { return }

            if let projects = projects {
                for project in projects {
                    self.preLoadNoteTitles(in: project)
                }
            }

            let terms = filter.split(separator: " ")
            let source = self.storage.noteList
            var notes = [Note]()

            for note in source {
                if operation.isCancelled {
                    completion()
                    return
                }

                if self.isFit(note: note, filter: filter, terms: terms, projects: projects, type: type, sidebarName: sidebarName) {
                    notes.append(note)
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
                    self.editArea.clear()
                    self.notesTableView.reloadData()
                    completion()
                }
                return
            }

            let note = self.notesTableView.noteList[0]

            DispatchQueue.main.async {
                self.notesTableView.reloadData()

                if search {
                    if self.notesTableView.noteList.count > 0 {
                        if filter.count > 0, note.title.lowercased() == self.search.stringValue.lowercased() {
                            self.selectNullTableRow(timer: true)
                        } else {
                            self.editArea.clear()
                        }
                    } else {
                        self.editArea.clear()
                    }
                }

                completion()
            }
        }

        searchQueue.addOperation(operation)
    }

    /*
     Load titles in cases sort by Title
     */
    private func preLoadNoteTitles(in project: Project) {
        if UserDefaultsManagement.sort == .title || project.sortBy == .title {
            _ = storage.noteList.filter { $0.project == project }
        }
    }

    private func isMatched(note: Note, terms: [Substring]) -> Bool {
        for term in terms {
            if note.name.range(of: term, options: .caseInsensitive, range: nil, locale: nil) != nil || note.content.string.range(of: term, options: .caseInsensitive, range: nil, locale: nil) != nil {
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
            && (filter.isEmpty || isMatched(note: note, terms: terms!)
            ) && (
                type == .All && note.project.showInCommon
                    || (
                        type != .All && projects!.contains(note.project)
                            || (note.project.parent != nil && projects!.contains(note.project.parent!))
                    )
                    || type == .Trash
            ) && (
                type == .Trash && note.isTrash()
                    || type != .Trash && !note.isTrash()
            )
    }

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
    }

    func focusEditArea(firstResponder: NSResponder? = nil) {
        var resp: NSResponder = editArea
        if let responder = firstResponder {
            resp = responder
        }

        if notesTableView.selectedRow > -1 {
            DispatchQueue.main.async {
                self.editArea.isEditable = true
                self.emptyEditAreaView.isHidden = true
                self.titleBarView.isHidden = false
                self.editArea.window?.makeFirstResponder(resp)
                self.editArea.restoreCursorPosition()
            }
            return
        }

        editArea.window?.makeFirstResponder(resp)
    }

    func focusTable() {
        DispatchQueue.main.async {
            let index = self.notesTableView.selectedRow > -1 ? self.notesTableView.selectedRow : 0
            self.notesTableView.window?.makeFirstResponder(self.notesTableView)
            self.notesTableView.selectRowIndexes([index], byExtendingSelection: true)
            self.notesTableView.scrollRowToVisible(index)
        }
    }

    func cleanSearchAndEditArea() {
        search.stringValue = ""
        search.becomeFirstResponder()

        notesTableView.selectRowIndexes(IndexSet(), byExtendingSelection: false)
        editArea.clear()
    }

    func makeNoteShortcut() {
        let clipboard = NSPasteboard.general.string(forType: NSPasteboard.PasteboardType.string)
        if clipboard != nil {
            let project = Storage.sharedInstance().getMainProject()
            createNote(content: clipboard!, project: project)

            let notification = NSUserNotification()
            notification.title = "妙言"
            notification.informativeText = "复制保存成功"
            notification.soundName = NSUserNotificationDefaultSoundName
            NSUserNotificationCenter.default.deliver(notification)
        }
    }

    func searchShortcut() {
        guard let mainWindow = MainWindowController.shared() else { return }

        if
            NSApplication.shared.isActive,
            !NSApplication.shared.isHidden,
            !mainWindow.isMiniaturized
        {
            NSApplication.shared.hide(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(self)

        guard let controller = mainWindow.contentViewController as? ViewController
        else { return }

        mainWindow.makeFirstResponder(controller.search)
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

    func createNote(name: String = "", content: String = "", type: NoteType? = nil, project: Project? = nil, load: Bool = false) {
        guard let vc = ViewController.shared() else { return }

        let selectedProjects = vc.storageOutlineView.getSidebarProjects()
        var sidebarProject = project ?? selectedProjects?.first
        let text = content

        if sidebarProject == nil {
            let projects = storage.getProjects()
            sidebarProject = projects.first
        }

        guard let project = sidebarProject else { return }

        let note = Note(name: name, project: project, type: type)
        note.content = NSMutableAttributedString(string: text)
        note.save()

        if let selectedProjects = selectedProjects, !selectedProjects.contains(project) {
            return
        }

        disablePreview()
        notesTableView.deselectNotes()
        editArea.string = text
        EditTextView.note = note
        search.stringValue.removeAll()
        updateTable {
            DispatchQueue.main.async {
                if let index = self.notesTableView.getIndex(note) {
                    self.notesTableView.selectRowIndexes([index], byExtendingSelection: false)
                    self.notesTableView.scrollRowToVisible(index)
                }
            }
        }
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

    func pin(_ selectedRows: IndexSet) {
        guard !selectedRows.isEmpty, let notes = filteredNoteList, var state = filteredNoteList else { return }

        var updatedNotes = [(Int, Note)]()
        for row in selectedRows {
            guard let rowView = notesTableView.rowView(atRow: row, makeIfNecessary: false) as? NoteRowView,
                  let cell = rowView.view(atColumn: 0) as? NoteCellView,
                  let note = cell.objectValue as? Note
            else { continue }

            updatedNotes.append((row, note))
            note.togglePin()
            cell.renderPin()
        }

        let resorted = storage.sortNotes(noteList: notes, filter: search.stringValue)
        let indexes = updatedNotes.compactMap { _, note in resorted.firstIndex(where: { $0 === note }) }
        let newIndexes = IndexSet(indexes)

        notesTableView.beginUpdates()
        let nowPinned = updatedNotes.filter { _, note in note.isPinned }
        for (row, note) in nowPinned {
            guard let newRow = resorted.firstIndex(where: { $0 === note }) else { continue }
            notesTableView.moveRow(at: row, to: newRow)
            let toMove = state.remove(at: row)
            state.insert(toMove, at: newRow)
        }

        let nowUnpinned = updatedNotes
            .filter { _, note -> Bool in !note.isPinned }
            .compactMap { _, note -> (Int, Note)? in
                guard let curRow = state.firstIndex(where: { $0 === note }) else { return nil }
                return (curRow, note)
            }
        for (row, note) in nowUnpinned.reversed() {
            guard let newRow = resorted.firstIndex(where: { $0 === note }) else { continue }
            notesTableView.moveRow(at: row, to: newRow)
            let toMove = state.remove(at: row)
            state.insert(toMove, at: newRow)
        }

        notesTableView.noteList = resorted
        notesTableView.reloadData(forRowIndexes: newIndexes, columnIndexes: [0])
        notesTableView.selectRowIndexes(newIndexes, byExtendingSelection: false)
        notesTableView.endUpdates()

        filteredNoteList = resorted
    }

    func enablePreview() {
        // Preview mode doesn't support text search
        cancelTextSearch()

        guard let vc = ViewController.shared() else { return }
        vc.editArea.window?.makeFirstResponder(vc.notesTableView)

        view.window!.title = NSLocalizedString("妙言「预览」", comment: "")
        UserDefaultsManagement.preview = true
        refillEditArea()
    }

    func disablePreview() {
        view.window!.title = NSLocalizedString("妙言「编辑」", comment: "")
        UserDefaultsManagement.preview = false

        editArea.markdownView?.removeFromSuperview()
        editArea.markdownView = nil

        guard let editor = editArea else { return }
        editor.subviews.removeAll(where: { $0.isKind(of: MPreviewView.self) })

        refillEditArea()
    }

    func togglePreview() {
        titleLabel.saveTitle()
        if UserDefaultsManagement.preview {
            disablePreview()
        } else {
            enablePreview()
        }
    }

    func loadMoveMenu() {
        guard let vc = ViewController.shared(), let note = vc.notesTableView.getSelectedNote() else { return }

        let moveTitle = NSLocalizedString("Move", comment: "Menu")
        if let prevMenu = noteMenu.item(withTitle: moveTitle) {
            noteMenu.removeItem(prevMenu)
        }

        let moveMenuItem = NSMenuItem()
        moveMenuItem.title = NSLocalizedString("Move", comment: "Menu")

        noteMenu.addItem(moveMenuItem)
        let moveMenu = NSMenu()

        if !note.isTrash() {
            let trashMenu = NSMenuItem()
            trashMenu.title = NSLocalizedString("Trash", comment: "Sidebar label")
            trashMenu.action = #selector(vc.deleteNote(_:))
            trashMenu.tag = 555
            moveMenu.addItem(trashMenu)
            moveMenu.addItem(NSMenuItem.separator())
        }

        let projects = storage.getProjects()
        for item in projects {
            if note.project == item || item.isTrash {
                continue
            }

            let menuItem = NSMenuItem()
            menuItem.title = item.label
            menuItem.representedObject = item
            menuItem.action = #selector(vc.moveNote(_:))
            moveMenu.addItem(menuItem)
        }

        let personalSelection = [
            "noteMove.print",
            "noteMove.copyTitle",
            "noteMove.copyUrl",
            "noteMove.rename"
        ]

        for menu in noteMenu.items {
            if let identifier = menu.identifier?.rawValue,
               personalSelection.contains(identifier)
            {
                menu.isHidden = (vc.notesTableView.selectedRowIndexes.count > 1)
            }
        }

        noteMenu.setSubmenu(moveMenu, for: moveMenuItem)
    }

    func loadSortBySetting() {
        let viewLabel = NSLocalizedString("View", comment: "Menu")
        let sortByLabel = NSLocalizedString("Sort by", comment: "View menu")

        guard
            let menu = NSApp.menu,
            let view = menu.item(withTitle: viewLabel),
            let submenu = view.submenu,
            let sortMenu = submenu.item(withTitle: sortByLabel),
            let sortItems = sortMenu.submenu
        else {
            return
        }

        let sort = UserDefaultsManagement.sort

        for item in sortItems.items {
            if let id = item.identifier, id.rawValue == "SB.\(sort.rawValue)" {
                item.state = NSControl.StateValue.on
            }
        }
    }

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

    func checkSidebarConstraint() {
        if sidebarSplitView.subviews[0].frame.width > 50 {
            searchTopConstraint.constant = 8
            return
        }

        if sidebarSplitView.subviews[0].frame.width < 50 {
            searchTopConstraint.constant = CGFloat(25)
            return
        }

        searchTopConstraint.constant = 8
    }

    @IBAction func duplicate(_ sender: Any) {
        if let notes = notesTableView.getSelectedNotes() {
            for note in notes {
                guard let name = note.getDupeName() else { continue }

                let noteDupe = Note(name: name, project: note.project, type: note.type)
                noteDupe.content = NSMutableAttributedString(string: note.content.string)

                // Clone images
                if note.type == .Markdown, note.container == .none {
                    let images = note.getAllImages()
                    for image in images {
                        move(note: noteDupe, from: image.url, imagePath: image.path, to: note.project, copy: true)
                    }
                }

                noteDupe.save()

                storage.add(noteDupe)
                notesTableView.insertNew(note: noteDupe)
            }
        }
    }

    @IBAction func noteCopy(_ sender: Any) {
        guard let fr = view.window?.firstResponder else { return }

        if fr.isKind(of: EditTextView.self) {
            editArea.copy(sender)
        }

        if fr.isKind(of: NotesTableView.self) {
            saveTextAtClipboard()
        }
    }

    @IBAction func copyURL(_ sender: Any) {
        if let note = notesTableView.getSelectedNote(), let title = note.title.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
            let name = "miaoyan://find/\(title)"
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(name, forType: NSPasteboard.PasteboardType.string)

            let notification = NSUserNotification()
            notification.title = "妙言"
            notification.informativeText = NSLocalizedString("URL has been copied to clipboard", comment: "")
            notification.soundName = NSUserNotificationDefaultSoundName
            NSUserNotificationCenter.default.deliver(notification)
        }
    }

    @IBAction func copyTitle(_ sender: Any) {
        if let note = notesTableView.getSelectedNote() {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(note.title, forType: NSPasteboard.PasteboardType.string)
        }
    }

    public func updateTitle(newTitle: String) {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "MiaoYan"

        var titleString = newTitle

        if newTitle.isValidUUID {
            titleString = String()
        }
        titleLabel.stringValue = titleString

        titleLabel.currentEditor()?.selectedRange = NSRange(location: titleString.utf16.count, length: 0)

        MainWindowController.shared()?.title = appName
    }

    // MARK: Share Service

    @IBAction func togglePreview(_ sender: NSButton) {
        togglePreview()
    }

    public func saveTextAtClipboard() {
        if let note = notesTableView.getSelectedNote() {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(note.content.string, forType: NSPasteboard.PasteboardType.string)
        }
    }

    public func saveHtmlAtClipboard() {
        if let note = notesTableView.getSelectedNote() {
            if let render = renderMarkdownHTML(markdown: note.content.string) {
                let pasteboard = NSPasteboard.general
                pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
                pasteboard.setString(render, forType: NSPasteboard.PasteboardType.string)
            }
        }
    }

    @IBAction func textFinder(_ sender: NSMenuItem) {
        guard let vc = ViewController.shared() else { return }

        if !vc.editAreaScroll.isFindBarVisible, [NSFindPanelAction.next.rawValue, NSFindPanelAction.previous.rawValue].contains(UInt(sender.tag)) {
            if UserDefaultsManagement.preview, vc.notesTableView.selectedRow > -1 {
                vc.disablePreview()
            }

            let menu = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            menu.tag = NSTextFinder.Action.showFindInterface.rawValue
            vc.editArea.performTextFinderAction(menu)
        }

        DispatchQueue.main.async {
            vc.editArea.performTextFinderAction(sender)
        }
    }

    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        for item in menu.items {
            if item.title == NSLocalizedString("Copy Link", comment: "") {
                item.action = #selector(NSText.copy(_:))
            }
        }

        return menu
    }

    func splitViewWillResizeSubviews(_ notification: Notification) {
        editArea.updateTextContainerInset()
    }

    public static func shared() -> ViewController? {
        guard let delegate = NSApplication.shared.delegate as? AppDelegate else { return nil }

        return delegate.mainWindowController?.window?.contentViewController as? ViewController
    }

    public func copy(project: Project, url: URL) -> URL {
        let fileName = url.lastPathComponent

        do {
            let destination = project.url.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            var tempUrl = url

            let ext = tempUrl.pathExtension
            tempUrl.deletePathExtension()

            let name = tempUrl.lastPathComponent
            tempUrl.deleteLastPathComponent()

            let now = DateFormatter().formatForDuplicate(Date())
            let baseUrl = project.url.appendingPathComponent(name + " " + now + "." + ext)

            try? FileManager.default.copyItem(at: url, to: baseUrl)

            return baseUrl
        }
    }
}
