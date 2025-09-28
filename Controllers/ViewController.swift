import Cocoa
import KeyboardShortcuts
import LocalAuthentication
import TelemetryDeck
import WebKit

extension KeyboardShortcuts.Name {
    static let activateWindow = Self("activateWindow", default: .init(.m, modifiers: [.command, .option]))
}

@MainActor
class ViewController:
    NSViewController,
    NSTextViewDelegate,
    NSPopoverDelegate,
    NSTextFieldDelegate,
    NSSplitViewDelegate,
    NSOutlineViewDelegate,
    NSOutlineViewDataSource,
    NSMenuItemValidation,
    NSUserNotificationCenterDelegate
{
    public var fsManager: FileSystemEventManager?
    var projectSettingsViewController: ProjectSettingsViewController?
    let storage = Storage.sharedInstance()
    var filteredNoteList: [Note]?
    var alert: NSAlert?
    var refilled: Bool = false
    var timer = Timer()
    var sidebarTimer = Timer()
    var rowUpdaterTimer = Timer()
    let searchQueue = OperationQueue()
    var isFocusedTitle: Bool = false
    var formatContent: String = ""
    var isFormatting: Bool = false
    var needRestorePreview: Bool = false
    private var disablePreviewWorkItem: DispatchWorkItem?
    var isHandlingScrollEvent = false
    var swipeLeftExecuted = false
    var swipeRightExecuted = false
    var scrollDeltaX: CGFloat = 0
    var updateViews = [Note]()
    public var breakUndoTimer = Timer()

    // Presentation mode scroll position preservation
    var savedPresentationScrollPosition: CGPoint?
    override var representedObject: Any? {
        didSet {}
    }
    @IBOutlet var emptyEditTitle: NSTextField!
    @IBOutlet var emptyEditAreaImage: NSImageView!
    @IBOutlet var emptyEditAreaView: NSView!
    @IBOutlet var splitView: EditorSplitView!
    @IBOutlet var editArea: EditTextView!
    @IBOutlet var editAreaScroll: EditorScrollView!
    @IBOutlet var search: SearchTextField!
    @IBOutlet var miaoYanText: NSTextField!
    @IBOutlet var notesTableView: NotesTableView!
    @IBOutlet var noteMenu: NSMenu! {
        didSet {
            noteMenu.setMenuItemIdentifier("noteMenu.export", forTitle: I18n.str("Export"))
        }
    }
    @IBOutlet var storageOutlineView: SidebarProjectView!
    @IBOutlet var sidebarSplitView: NSSplitView!
    @IBOutlet var notesListCustomView: NSView!
    @IBOutlet var outlineHeader: OutlineHeaderView!
    @IBOutlet var titiebarHeight: NSLayoutConstraint!
    @IBOutlet var searchTopConstraint: NSLayoutConstraint!
    @IBOutlet var titleLabel: TitleTextField!
    @IBOutlet var titleTopConstraint: NSLayoutConstraint!
    @IBOutlet var sortByOutlet: NSMenuItem! {
        didSet {
            sortByOutlet.setIdentifier("viewMenu.sortBy")
        }
    }

    @IBOutlet var titleBarAdditionalView: NSVisualEffectView! {
        didSet {
            let layer = CALayer()
            layer.frame = titleBarAdditionalView.bounds
            layer.backgroundColor = .clear
            titleBarAdditionalView.wantsLayer = true
            titleBarAdditionalView.layer = layer
            if UserDefaultsManagement.buttonShow == "Hover" {
                titleBarAdditionalView.alphaValue = 0
            } else {
                titleBarAdditionalView.alphaValue = 1
            }
        }
    }

    @IBOutlet var addProjectButton: NSButton! {
        didSet {
            let layer = CALayer()
            layer.frame = addProjectButton.bounds
            layer.backgroundColor = .clear
            addProjectButton.wantsLayer = true
            addProjectButton.layer = layer
            if UserDefaultsManagement.buttonShow == "Hover" {
                addProjectButton.alphaValue = 0
            } else {
                addProjectButton.alphaValue = 1
            }
        }
    }

    @IBOutlet var formatButton: NSButton!
    @IBOutlet var previewButton: NSButton! {
        didSet {
            previewButton.state = UserDefaultsManagement.preview ? .on : .off
        }
    }

    @IBOutlet var presentationButton: NSButton! {
        didSet {
            presentationButton.state = UserDefaultsManagement.presentation ? .on : .off
        }
    }

    @IBOutlet var descendingCheckItem: NSMenuItem! {
        didSet {
            ascendingCheckItem?.state = UserDefaultsManagement.sortDirection ? .off : .on
            descendingCheckItem?.state = UserDefaultsManagement.sortDirection ? .on : .off
        }
    }

    @IBOutlet var ascendingCheckItem: NSMenuItem! {
        didSet {
            ascendingCheckItem?.state = UserDefaultsManagement.sortDirection ? .off : .on
            descendingCheckItem?.state = UserDefaultsManagement.sortDirection ? .on : .off
        }
    }

    @IBOutlet var titleBarView: TitleBarView! {
        didSet {
            titleBarView.onMouseExitedClosure = { [weak self] in
                if UserDefaultsManagement.buttonShow != "Hover" {
                    return
                }
                DispatchQueue.main.async {
                    NSAnimationContext.runAnimationGroup(
                        { context in
                            context.duration = 0.20
                            self?.titleBarAdditionalView.alphaValue = 0
                        }, completionHandler: nil)
                }
            }
            titleBarView.onMouseEnteredClosure = { [weak self] in
                if UserDefaultsManagement.buttonShow != "Hover" {
                    return
                }
                DispatchQueue.main.async {
                    NSAnimationContext.runAnimationGroup(
                        { context in
                            context.duration = 0.20
                            self?.titleBarAdditionalView.alphaValue = 1
                        }, completionHandler: nil)
                }
            }
        }
    }

    @IBOutlet var projectHeaderView: OutlineHeaderView! {
        didSet {
            projectHeaderView.onMouseExitedClosure = { [weak self] in
                if UserDefaultsManagement.buttonShow != "Hover" {
                    return
                }
                DispatchQueue.main.async {
                    NSAnimationContext.runAnimationGroup(
                        { context in
                            context.duration = 0.20
                            self?.addProjectButton.alphaValue = 0
                        }, completionHandler: nil)
                }
            }
            projectHeaderView.onMouseEnteredClosure = { [weak self] in
                if UserDefaultsManagement.buttonShow != "Hover" {
                    return
                }
                DispatchQueue.main.async {
                    NSAnimationContext.runAnimationGroup(
                        { context in
                            context.duration = 0.20
                            self?.addProjectButton.alphaValue = 1
                        }, completionHandler: nil)
                }
            }
        }
    }

    @IBOutlet var sidebarScrollView: NSScrollView!
    @IBOutlet var notesScrollView: NSScrollView!
    lazy var popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.contentViewController = ContentViewController()
        popover.delegate = self
        return popover
    }()

    // MARK: - Apply live UI preferences
    public func applyInterfacePreferences() {
        search.font = UserDefaultsManagement.searchFont
        titleLabel.font = UserDefaultsManagement.titleFont.titleBold()
        emptyEditTitle.font = UserDefaultsManagement.emptyEditTitleFont

        storageOutlineView.reloadData()
        notesTableView.reloadData()

        setTableRowHeight()
        storageOutlineView.needsDisplay = true
        notesTableView.needsDisplay = true
    }

    public func applyButtonVisibilityPreference() {
        let showOnHover = (UserDefaultsManagement.buttonShow == "Hover")
        titleBarAdditionalView?.alphaValue = showOnHover ? 0 : 1
        addProjectButton?.alphaValue = showOnHover ? 0 : 1
    }

    @objc func detachedWindowWillClose(notification: NSNotification) {}

    override func viewDidLoad() {
        configureShortcuts()
        configureDelegates()
        configureLayout()
        configureNotesList()
        configureEditor()
        // Async preload to avoid impacting startup performance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.preloadWebView()
        }
        fsManager = FileSystemEventManager(storage: storage, delegate: self)
        fsManager?.start()
        loadMoveMenu()
        loadSortBySetting()
        checkSidebarConstraint()
        checkTitlebarTopConstraint()
        configureMenuIcons()
        #if CLOUDKIT
            registerKeyValueObserver()
        #endif
        searchQueue.maxConcurrentOperationCount = 1
        notesTableView.loadingQueue.maxConcurrentOperationCount = 1
        notesTableView.loadingQueue.qualityOfService = QualityOfService.userInteractive
    }

    // Handle webview performance impact from long-term inactivity
    override func viewDidDisappear() {
        super.viewWillDisappear()
        if UserDefaultsManagement.preview {
            disablePreviewWorkItem = DispatchWorkItem { [weak self] in
                self?.needRestorePreview = true
                self?.disablePreview()
            }
            // Delay preview disable by 30 minutes
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1800), execute: disablePreviewWorkItem!)
        } else {
            needRestorePreview = false
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if UserDefaultsManagement.preview {
            disablePreviewWorkItem?.cancel()
        }
        if needRestorePreview {
            if titleLabel.isEditable {
                fileName(titleLabel)
            }
            enablePreview()
        }
    }

    override func viewDidAppear() {
        if UserDefaultsManagement.fullScreen {
            view.window?.toggleFullScreen(nil)
        }
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            if let urls = appDelegate.urls {
                appDelegate.openNotes(urls: urls)
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
        handleForAppMode()
    }

    func handleForAppMode() {
        refreshMiaoYanNum()
        if UserDefaultsManagement.isSingleMode {
            toastInSingleMode()
        } else if UserDefaultsManagement.isFirstLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showSidebar("")
            }
            UserDefaultsManagement.isFirstLaunch = false
        } else {
            ensureInitialProjectSelection()
        }
    }

    private func ensureInitialProjectSelection() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard self.sidebarWidth > 0 && self.storageOutlineView.selectedRow == -1 else { return }
            // Try to find the project by URL first (more reliable after reordering)
            if let lastProjectURL = UserDataService.instance.lastProject,
                let items = self.storageOutlineView.sidebarItems
            {
                for (index, item) in items.enumerated() {
                    if let sidebarItem = item as? SidebarItem,
                        sidebarItem.project?.url == lastProjectURL
                    {
                        self.storageOutlineView.selectRowIndexes([index], byExtendingSelection: false)
                        return
                    }
                }
            }
            // Fallback to index-based selection if URL matching fails
            let lastProjectIndex = UserDefaultsManagement.lastProject
            if let items = self.storageOutlineView.sidebarItems,
                items.indices.contains(lastProjectIndex)
            {
                self.storageOutlineView.selectRowIndexes([lastProjectIndex], byExtendingSelection: false)
            } else if let items = self.storageOutlineView.sidebarItems, !items.isEmpty {
                self.storageOutlineView.selectRowIndexes([0], byExtendingSelection: false)
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let vc = ViewController.shared() else {
            return false
        }
        let canUseMenu = UserDefaultsManagement.canUseMenu
        if let title = menuItem.menu?.identifier?.rawValue {
            switch title {
            case "miaoyanMenu":
                if menuItem.identifier?.rawValue == "emptyTrashMenu" {
                    menuItem.keyEquivalentModifierMask = [.command, .option, .shift]
                    return canUseMenu
                }
            case "fileMenu":
                if menuItem.identifier?.rawValue == "fileMenu.delete" {
                    menuItem.keyEquivalentModifierMask = [.command]
                }
                if ["fileMenu.new", "fileMenu.searchAndCreate", "fileMenu.open"].contains(menuItem.identifier?.rawValue) {
                    return canUseMenu
                }
                if vc.notesTableView.selectedRow == -1 {
                    return false
                }
            case "folderMenu":
                if ["folderMenu.newFolder", "folderMenu.showInFinder", "folderMenu.renameFolder"].contains(menuItem.identifier?.rawValue) {
                    return canUseMenu
                }
                guard let p = vc.getSidebarProject(), !p.isTrash else {
                    return false
                }
            case "findMenu":
                if ["findMenu.find", "findMenu.findAndReplace", "findMenu.next", "findMenu.prev"].contains(menuItem.identifier?.rawValue), vc.notesTableView.selectedRow > -1 {
                    return canUseMenu
                }
                return vc.editAreaScroll.isFindBarVisible || vc.editArea.hasFocus()
            default:
                break
            }
        }
        return true
    }

    private func configureLayout() {
        emptyEditAreaView.isHidden = true
        titleLabel.isHidden = true
        updateTitle(newTitle: "")
        DispatchQueue.main.async {
            self.editArea.updateTextContainerInset()
        }
        editArea.textContainerInset.height = 10
        editArea.isEditable = false
        editArea.layoutManager?.defaultAttachmentScaling = .scaleProportionallyDown
        search.font = UserDefaultsManagement.searchFont
        editArea.defaultParagraphStyle = NSTextStorage.getParagraphStyle()
        var typingAttrs: [NSAttributedString.Key: Any] = [
            .font: UserDefaultsManagement.noteFont!,
            .paragraphStyle: NSTextStorage.getParagraphStyle(),
        ]
        // Add letter spacing if enabled
        if UserDefaultsManagement.editorLetterSpacing != 0 {
            typingAttrs[.kern] = UserDefaultsManagement.editorLetterSpacing
        }
        editArea.typingAttributes = typingAttrs
        titleLabel.font = UserDefaultsManagement.titleFont.titleBold()
        emptyEditTitle.font = UserDefaultsManagement.emptyEditTitleFont
        setTableRowHeight()
        // Set up delegate and data source before loading data
        storageOutlineView.delegate = storageOutlineView
        storageOutlineView.dataSource = storageOutlineView
        storageOutlineView.sidebarItems = Sidebar().getList()
        storageOutlineView.reloadData()
        storageOutlineView.selectionHighlightStyle = .none
        // Ensure proper display after data is set
        storageOutlineView.needsDisplay = true
        sidebarSplitView.autosaveName = "SidebarSplitView"
        splitView.autosaveName = "EditorSplitView"
        // Assign an autosave name so the sidebar outline view keeps its expansion state
        storageOutlineView.autosaveExpandedItems = true
        storageOutlineView.autosaveName = "SidebarOutlineView"
        notesScrollView.scrollerStyle = .overlay
        sidebarScrollView.scrollerStyle = .overlay
        sidebarScrollView.horizontalScroller = .none
        sidebarScrollView.hasHorizontalScroller = false
        sidebarScrollView.autohidesScrollers = true
        // Keep the sidebar column width in sync with its parent view
        if let column = storageOutlineView.tableColumns.first {
            column.resizingMask = .autoresizingMask
            column.minWidth = 50
            column.maxWidth = 1000
        }
    }

    func configureNotesList() {
        var lastSidebarItem = UserDefaultsManagement.lastProject
        if UserDefaultsManagement.isSingleMode {
            lastSidebarItem = 0
        }
        updateTable {
            // Set sidebar selection after table update to properly trigger selection change
            if let items = self.storageOutlineView.sidebarItems, items.indices.contains(lastSidebarItem) {
                // Use a small delay to ensure table is fully loaded before selection
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.storageOutlineView.selectRowIndexes([lastSidebarItem], byExtendingSelection: false)
                }
            }
            if UserDefaultsManagement.isSingleMode {
                let singleModeUrl = URL(fileURLWithPath: UserDefaultsManagement.singleModePath)
                self.hideSidebar("")
                if !FileManager.default.directoryExists(atUrl: singleModeUrl), let lastNote = self.storage.getBy(url: singleModeUrl), let i = self.notesTableView.getIndex(lastNote) {
                    DispatchQueue.main.async {
                        self.notesTableView.selectRow(i)
                        self.notesTableView.scrollRowToVisible(row: i, animated: false)
                    }
                } else if FileManager.default.directoryExists(atUrl: singleModeUrl) {
                    DispatchQueue.main.async {
                        if !self.notesTableView.noteList.isEmpty {
                            self.notesTableView.selectRow(0)
                            self.notesTableView.scrollRowToVisible(row: 0, animated: false)
                        }
                    }
                }
                self.storageOutlineView.isLaunch = false
            }
        }
    }

    private func configureEditor() {
        editArea.usesFindBar = true
        editArea.isIncrementalSearchingEnabled = true
        editArea.isAutomaticLinkDetectionEnabled = false
        editArea.isAutomaticQuoteSubstitutionEnabled = false
        editArea.isAutomaticDataDetectionEnabled = false
        editArea.isAutomaticTextReplacementEnabled = false
        editArea.isAutomaticDashSubstitutionEnabled = false
        editArea.textStorage?.delegate = editArea.textStorage
        editArea?.linkTextAttributes = [
            .foregroundColor: Theme.highlightColor
        ]
        editArea.viewDelegate = self
    }

    private func configureShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .activateWindow) { [self] in
            activeShortcut()
        }
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
    // MARK: - Sidebar Layout Manager
    var selectRowTimer = Timer()
    // MARK: Share Service
    public static func shared() -> ViewController? {
        guard let delegate = NSApplication.shared.delegate as? AppDelegate else {
            return nil
        }
        return delegate.mainWindowController?.window?.contentViewController as? ViewController
    }

    // MARK: - NSTextViewDelegate
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? EditTextView,
            let note = EditTextView.note,
            textView == editArea
        else { return }
        editArea.saveTextStorageContent(to: note)
        note.save()
        if UserDefaultsManagement.preview || UserDefaultsManagement.magicPPT {
            refillEditArea(previewOnly: true, force: true)
        }
    }

    private func configureMenuIcons() {
        guard #available(macOS 11.0, *) else { return }
        if let mainMenu = NSApp.mainMenu {
            mainMenu.applyMenuIcons()
        }

        noteMenu.applyMenuIcons()

        if let sidebarMenu = storageOutlineView.menu {
            sidebarMenu.applyMenuIcons()
        }
    }
}
