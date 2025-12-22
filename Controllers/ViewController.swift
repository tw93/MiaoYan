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
    NSMenuItemValidation,
    NSUserNotificationCenterDelegate,
    MPreviewScrollDelegate
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
    nonisolated(unsafe) var liveResizeObserver: NSObjectProtocol?
    var needsPreviewLayoutAfterLiveResize = false
    var isHandlingScrollEvent = false
    var swipeLeftExecuted = false
    var swipeRightExecuted = false
    var scrollDeltaX: CGFloat = 0
    var updateViews = [Note]()
    public var breakUndoTimer = Timer()
    var lastEnablePreviewTime: TimeInterval = 0

    // Presentation mode scroll position preservation
    var savedPresentationScrollPosition: CGPoint?

    // Check if any preview mode is active
    var shouldShowPreview: Bool {
        UserDefaultsManagement.preview
            || UserDefaultsManagement.magicPPT
            || UserDefaultsManagement.presentation
            || UserDefaultsManagement.splitViewMode
    }

    override var representedObject: Any? {
        didSet {}
    }
    // Empty state UI (kept for Storyboard compatibility, hidden at runtime)
    @IBOutlet var emptyEditTitle: NSTextField!
    @IBOutlet var emptyEditAreaImage: NSImageView!
    @IBOutlet var emptyEditAreaView: NSView!
    @IBOutlet var splitView: EditorSplitView!
    @IBOutlet var editArea: EditTextView!
    @IBOutlet var editAreaScroll: EditorScrollView!

    var editorContentSplitView: EditorContentSplitView?
    var previewScrollView: EditorScrollView?
    nonisolated(unsafe) var splitScrollObserver: NSObjectProtocol?
    var isProgrammaticSplitScroll = false
    nonisolated(unsafe) var splitScrollDebounceTimer: Timer?
    var lastSyncedScrollRatio: CGFloat = -1  // Track last synced ratio to avoid redundant JS execution
    var needsEditorModeUpdateAfterPreview = false
    var isUnfoldingLayout = false
    @IBOutlet var search: SearchTextField!
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

    // Cached menu item references to avoid repeated lookups (internal access for extensions)
    var sortByOutlet: NSMenuItem?
    var descendingCheckItem: NSMenuItem?
    var ascendingCheckItem: NSMenuItem?

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

    @IBOutlet var toggleListButton: NSButton!
    @IBOutlet var toggleSplitButton: NSButton!
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

    // Cache menu item references to avoid repeated menu tree traversals
    private func cacheMenuItems() {
        // Use identifier-based lookup to be locale-independent
        if let viewMenu = NSApp.mainMenu?.items.first(where: { $0.submenu?.identifier == NSUserInterfaceItemIdentifier("viewMenu") })?.submenu {
            sortByOutlet = viewMenu.items.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("viewMenu.sortBy") })

            if let sortByMenu = sortByOutlet?.submenu {
                descendingCheckItem = sortByMenu.items.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("Descending") })
                ascendingCheckItem = sortByMenu.items.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("Ascending") })
            }
        }
    }

    func updateSortMenuState() {
        // Ensure menu items are cached before updating state
        guard let ascending = ascendingCheckItem, let descending = descendingCheckItem else {
            cacheMenuItems()
            guard let ascending = ascendingCheckItem, let descending = descendingCheckItem else { return }
            ascending.state = UserDefaultsManagement.sortDirection ? .off : .on
            descending.state = UserDefaultsManagement.sortDirection ? .on : .off
            return
        }
        ascending.state = UserDefaultsManagement.sortDirection ? .off : .on
        descending.state = UserDefaultsManagement.sortDirection ? .on : .off
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

    deinit {
        // Clean up scroll sync resources
        if let observer = splitScrollObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        splitScrollDebounceTimer?.invalidate()
        if let observer = liveResizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewDidLoad() {
        // Hide empty state UI (no longer used)
        emptyEditAreaView.isHidden = true
        configureShortcuts()
        configureDelegates()
        configureLayout()
        configureNotesList()
        configureEditor()

        // Pre-hide editor if starting in preview mode to avoid white flash
        // Pre-hide editor to avoid white flash/empty state during initial load
        editAreaScroll.alphaValue = 0
        titleLabel.alphaValue = 0

        // Async preload to avoid impacting startup performance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.preloadWebView()
        }
        fsManager = FileSystemEventManager(storage: storage, delegate: self)
        fsManager?.start()
        loadMoveMenu()
        cacheMenuItems()

        // Apply modern icons to menus
        if #available(macOS 11.0, *) {
            noteMenu.applyMenuIcons()
            storageOutlineView.menu?.applyMenuIcons()
        }

        updateSortMenuState()
        checkSidebarConstraint()
        checkTitlebarTopConstraint()
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
        removeLiveResizeObserver()
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

            // Only pre-configure if not already configured (first appearance or after being hidden)
            let needsConfiguration = editorContentSplitView?.displayMode != .previewOnly || editArea.markdownView == nil || editArea.markdownView?.isHidden == true

            if needsConfiguration {
                // Pre-configure preview UI state before view appears to avoid white flash
                editorContentSplitView?.setDisplayMode(.previewOnly, animated: false)
                preparePreviewContainer(hidden: false)
                editAreaScroll.hasVerticalScroller = false
                editAreaScroll.hasHorizontalScroller = false
            }
        }
        if needRestorePreview {
            if titleLabel.isEditable {
                fileName(titleLabel)
            }
            enablePreview()
        }
    }

    override func viewDidAppear() {
        installLiveResizeObserverIfNeeded()
        // Safety check: If data loaded very quickly (before window was attached), the reveal call might have been missed.
        // If window is still invisible but we have data, reveal it now.
        if let window = view.window, window.alphaValue == 0, !notesTableView.noteList.isEmpty {
            if let wc = window.windowController as? MainWindowController {
                wc.revealWindowWhenReady()
            }
        }

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
        applyEditorModePreferenceChange()

        // Restore Preview Mode if needed
        if UserDefaultsManagement.preview {
            // If a note is already selected, enable preview immediately
            if notesTableView.selectedRow >= 0 {
                enablePreview()
            } else {
                // Otherwise, wait briefly for note selection to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if UserDefaultsManagement.preview {
                        self.enablePreview()
                    }
                }
            }
        }
    }

    private func installLiveResizeObserverIfNeeded() {
        guard liveResizeObserver == nil, let window = view.window else { return }
        liveResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.handleWindowDidEndLiveResize()
        }
    }

    private func removeLiveResizeObserver() {
        if let observer = liveResizeObserver {
            NotificationCenter.default.removeObserver(observer)
            liveResizeObserver = nil
        }
        needsPreviewLayoutAfterLiveResize = false
    }

    func handleForAppMode() {
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

    // MARK: - Selection Management

    /// Ensures a note is selected when none is currently selected (unified auto-select logic)
    /// - Parameters:
    ///   - preferLastSelected: If true, tries to restore last selected note before falling back to first note
    ///   - preserveScrollPosition: If true, skips forcing the note list to scroll the selected row into view
    func ensureNoteSelection(preferLastSelected: Bool = false, preserveScrollPosition: Bool = false) {
        guard notesTableView.selectedRow == -1,
            !notesTableView.noteList.isEmpty,
            !UserDefaultsManagement.isSingleMode
        else {
            return
        }

        var targetIndex = 0
        var restoredLastSelection = false

        if preferLastSelected,
            let lastURL = UserDefaultsManagement.lastSelectedURL,
            let lastNote = storage.getBy(url: lastURL),
            let index = notesTableView.getIndex(lastNote)
        {
            targetIndex = index
            restoredLastSelection = true
        }

        let shouldEnsureVisibility = !restoredLastSelection && !preserveScrollPosition
        notesTableView.selectRow(
            targetIndex,
            ensureVisible: shouldEnsureVisibility,
            suppressSideEffects: restoredLastSelection
        )
        if restoredLastSelection {
            notesTableView.restoreScrollPosition(ensureSelectionVisible: false)
        }
    }

    func persistCurrentViewState() {
        if let sidebar = storageOutlineView {
            let selectedRow = sidebar.selectedRow
            if selectedRow >= 0 {
                UserDefaultsManagement.lastProject = selectedRow

                if let item = sidebar.item(atRow: selectedRow) as? SidebarItem {
                    UserDataService.instance.lastType = item.type.rawValue
                    UserDataService.instance.lastProject = item.project?.url
                    UserDataService.instance.lastName = item.name
                }
            }
        }

        if let selectedNote = notesTableView.getSelectedNote() {
            UserDefaultsManagement.lastSelectedURL = selectedNote.url
        }

        notesTableView.saveScrollPosition()
    }

    private func ensureInitialProjectSelection() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Skip if a project is already selected
            guard self.storageOutlineView.selectedRow == -1 else { return }

            var targetIndex: Int?

            // Try to find the project by URL first (more reliable after reordering)
            if let lastProjectURL = UserDataService.instance.lastProject,
                let items = self.storageOutlineView.sidebarItems
            {
                if let index = items.firstIndex(where: { ($0 as? SidebarItem)?.project?.url == lastProjectURL }) {
                    targetIndex = index
                }
            }

            // Fallback to index-based selection if URL matching fails
            if targetIndex == nil {
                let lastProjectIndex = UserDefaultsManagement.lastProject
                if let items = self.storageOutlineView.sidebarItems,
                    items.indices.contains(lastProjectIndex)
                {
                    targetIndex = lastProjectIndex
                } else if let items = self.storageOutlineView.sidebarItems, !items.isEmpty {
                    targetIndex = 0
                }
            }

            if let index = targetIndex {
                self.storageOutlineView.selectRowIndexes([index], byExtendingSelection: false)

                // Fix: Manually trigger delegate if view is hidden (suppressed notifications)
                // This ensures updateTable is called to populate the note list even in Focus Mode
                if self.storageOutlineView.isHidden || self.storageOutlineView.frame.width == 0 {
                    self.storageOutlineView.outlineViewSelectionDidChange(
                        Notification(name: NSOutlineView.selectionDidChangeNotification, object: self.storageOutlineView)
                    )
                }
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let vc = ViewController.shared() else {
            return false
        }

        if menuItem.action == #selector(exportMiaoYanPPT(_:)) {
            return vc.isMiaoYanPPT(needToast: false)
        }

        let canUseMenu = UserDefaultsManagement.canUseMenu
        if let title = menuItem.menu?.identifier?.rawValue {
            switch title {
            case "miaoyanMenu":
                if menuItem.identifier?.rawValue == "cleanAttachmentsMenu" {
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
                let isPreviewSearchVisible = vc.editArea.markdownView?.isSearchBarVisible ?? false
                return vc.editArea.isSearchBarVisible || isPreviewSearchVisible || vc.editArea.hasFocus()
            default:
                break
            }
        }
        return true
    }

    private func configureLayout() {
        guard let parent = formatButton?.superview else { return }

        // Adjust parent width to accommodate new buttons
        for constraint in parent.constraints {
            if constraint.firstAttribute == .width && constraint.constant == 140 {
                constraint.constant = 180
                break
            }
        }

        // Set custom icons for formatButton, previewButton, presentationButton
        if let image = NSImage(named: "icon_format") {
            image.isTemplate = true
            formatButton.image = image
        }
        if let image = NSImage(named: "icon_preview") {
            image.isTemplate = true
            previewButton.image = image
        }
        if let image = NSImage(named: "icon_presentation") {
            image.isTemplate = true
            presentationButton.image = image
        }

        formatButton.toolTip = I18n.str("Format")
        previewButton.toolTip = I18n.str("Toggle Preview")
        presentationButton.toolTip = I18n.str("Presentation")

        // Unify button sizes: set all to 18x18 and remove borders/backgrounds for consistency
        for button in [formatButton, previewButton, presentationButton] {
            guard let btn = button else { continue }

            // Unify style to match programmatically created buttons
            btn.isBordered = false
            btn.bezelStyle = .texturedRounded
            btn.contentTintColor = .secondaryLabelColor
            btn.imagePosition = .imageOnly

            for constraint in btn.constraints {
                if constraint.firstAttribute == .width {
                    constraint.constant = 24
                } else if constraint.firstAttribute == .height {
                    constraint.constant = 24
                }
            }
        }

        // Create toggleSplitButton first (relative to formatButton to avoid overlap)
        if toggleSplitButton == nil {
            let button = NSButton()
            button.translatesAutoresizingMaskIntoConstraints = false
            button.bezelStyle = .texturedRounded

            // Use custom icons for two states (single/split)
            let iconName = UserDefaultsManagement.splitViewMode ? "icon_editor_split" : "icon_editor_single"
            if let image = NSImage(named: iconName) {
                image.isTemplate = true
                button.image = image
            }

            button.target = self
            button.action = #selector(toggleSplitMode(_:))
            button.isBordered = false
            button.contentTintColor = .secondaryLabelColor
            button.toolTip = I18n.str("Toggle Split Mode")

            toggleSplitButton = button
        }

        // Create toggleListButton first (leftmost position)
        if toggleListButton == nil {
            let listButton = NSButton()
            listButton.translatesAutoresizingMaskIntoConstraints = false
            listButton.bezelStyle = .texturedRounded
            listButton.imagePosition = .imageOnly

            // Use custom icon
            if let image = NSImage(named: "icon_sidebar_left") {
                image.isTemplate = true
                listButton.image = image
            }

            listButton.target = self
            listButton.action = #selector(toggleLayoutCycle(_:))
            listButton.isBordered = false
            listButton.contentTintColor = .secondaryLabelColor
            listButton.toolTip = I18n.str("Toggle Note List")

            parent.addSubview(listButton)
            listButton.wantsLayer = true
            listButton.layer?.zPosition = 100

            // Position: align to parent leading edge with proper spacing
            NSLayoutConstraint.activate([
                listButton.centerYAnchor.constraint(equalTo: formatButton.centerYAnchor),
                listButton.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 8),
                listButton.widthAnchor.constraint(equalToConstant: 24),
                listButton.heightAnchor.constraint(equalToConstant: 24),
            ])
            toggleListButton = listButton
        }

        // Setup constraints for toggleSplitButton after both buttons are created
        if let splitButton = toggleSplitButton, let listButton = toggleListButton {
            parent.addSubview(splitButton)

            // Recommended Order: List -> Format -> Split -> Preview -> Presentation
            // 1. List (Sidebar) - Navigation Context
            // 2. Format (Action) - Content Modification
            // 3. Split (Layout) - View Experience
            // 4. Preview (Mode) - View Experience
            // 5. Presentation (Mode) - Immersive Experience

            // Reset constraints for all movable buttons to ensure clean slate
            for btn in [formatButton, previewButton, presentationButton] {
                guard let btn = btn else { continue }
                for constraint in parent.constraints {
                    if constraint.firstItem as? NSButton == btn && constraint.firstAttribute == .leading {
                        constraint.isActive = false
                    }
                }
            }

            // 1. List is anchored to parent leading (set in creation block above)

            // 2. Format follows List (Uniform gap: 8)
            NSLayoutConstraint.activate([
                formatButton.leadingAnchor.constraint(equalTo: listButton.trailingAnchor, constant: 8)
            ])

            // 3. Split follows Format (Uniform gap: 8)
            NSLayoutConstraint.activate([
                splitButton.centerYAnchor.constraint(equalTo: formatButton.centerYAnchor),
                splitButton.leadingAnchor.constraint(equalTo: formatButton.trailingAnchor, constant: 8),
                splitButton.widthAnchor.constraint(equalToConstant: 24),
                splitButton.heightAnchor.constraint(equalToConstant: 24),
            ])

            // 4. Preview follows Split (Uniform gap: 8)
            NSLayoutConstraint.activate([
                previewButton.centerYAnchor.constraint(equalTo: formatButton.centerYAnchor),
                previewButton.leadingAnchor.constraint(equalTo: splitButton.trailingAnchor, constant: 8),
            ])

            // 5. Presentation follows Preview (Uniform gap: 8)
            NSLayoutConstraint.activate([
                presentationButton.centerYAnchor.constraint(equalTo: formatButton.centerYAnchor),
                presentationButton.leadingAnchor.constraint(equalTo: previewButton.trailingAnchor, constant: 8),
            ])
        }

        titleLabel.isHidden = true
        updateTitle(newTitle: "")
        DispatchQueue.main.async {
            self.editArea.updateTextContainerInset()
        }
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
        // Configure split view for editor content
        configureEditorContentSplitView()
        ensurePanelsVisibleAtStartup()
    }

    private func configureEditorContentSplitView() {
        guard let editAreaScrollParent = editAreaScroll.superview else { return }

        // Create EditorContentSplitView with proper frame
        let splitViewFrame = editAreaScroll.frame
        let contentSplitView = EditorContentSplitView(frame: splitViewFrame)
        contentSplitView.delegate = contentSplitView
        contentSplitView.autoresizingMask = [.width, .height]

        // Create preview scroll view with same frame as editor
        let previewScroll = EditorScrollView(frame: splitViewFrame)
        previewScroll.autoresizingMask = [.width, .height]
        previewScroll.hasVerticalScroller = true
        previewScroll.hasHorizontalScroller = false
        previewScroll.autohidesScrollers = true
        previewScroll.drawsBackground = false
        previewScroll.scrollerStyle = .overlay

        // Remove storyboard min-width constraint so split panes can evenly share space
        let minWidthConstraints = editAreaScroll.constraints.filter {
            $0.identifier == "1Ss-OK-0sm" || ($0.firstAttribute == .width && $0.relation == .greaterThanOrEqual && $0.secondItem == nil)
        }
        NSLayoutConstraint.deactivate(minWidthConstraints)

        // Replace editAreaScroll in hierarchy
        editAreaScroll.removeFromSuperview()
        editAreaScrollParent.addSubview(contentSplitView)

        // Pin split view to fill the editor container so both panes get real frames
        contentSplitView.translatesAutoresizingMaskIntoConstraints = false
        let topAnchor = titleBarView?.bottomAnchor ?? editAreaScrollParent.topAnchor
        NSLayoutConstraint.activate([
            contentSplitView.leadingAnchor.constraint(equalTo: editAreaScrollParent.leadingAnchor),
            contentSplitView.trailingAnchor.constraint(equalTo: editAreaScrollParent.trailingAnchor),
            contentSplitView.topAnchor.constraint(equalTo: topAnchor),
            contentSplitView.bottomAnchor.constraint(equalTo: editAreaScrollParent.bottomAnchor),
        ])

        // Reset editAreaScroll frame and autoresizing
        editAreaScroll.frame = splitViewFrame
        editAreaScroll.autoresizingMask = [.width, .height]

        // Add both scroll views to split view using addArrangedSubview (required for NSSplitView)
        contentSplitView.addArrangedSubview(editAreaScroll)
        contentSplitView.addArrangedSubview(previewScroll)
        previewScroll.isHidden = true

        // Store references
        self.editorContentSplitView = contentSplitView
        self.previewScrollView = previewScroll

        contentSplitView.onResize = { [weak self] in
            self?.handleEditorContentResize()
        }

        // Set initial mode to editor only
        contentSplitView.setDisplayMode(.editorOnly, animated: false)
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

            // Trigger window fade-in now that data is loaded and initial Note is selected
            if let windowController = self.view.window?.windowController as? MainWindowController {
                windowController.revealWindowWhenReady()
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

    func revealEditor() {
        guard editAreaScroll.alphaValue == 0 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.editAreaScroll.animator().alphaValue = 1
            self.titleLabel.animator().alphaValue = 1
        }
    }
}
