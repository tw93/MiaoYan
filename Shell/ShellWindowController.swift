import AppKit
import KeyboardShortcuts
import SwiftUI

/// Hosts the SwiftUI shell in a window of its own. Until it reaches parity
/// with the storyboard window it opens only when launched with
/// `-MiaoYanShell YES` (an Xcode scheme argument), so the shipping window is
/// untouched.
@available(macOS 14, *)
final class ShellWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private var appearanceObservation: NSKeyValueObservation?
    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: "MiaoYanShell")
    }

    let model = ShellModel()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 720, height: 420)
        window.backgroundColor = ShellPalette.background
        window.isReleasedWhenClosed = false
        // An empty unified toolbar gives the title bar Notes' 52pt height and
        // centres the traffic lights in it; the columns draw their own
        // controls on that line.
        window.toolbar = NSToolbar(identifier: "MiaoYanShellToolbar")
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        super.init(window: window)

        window.contentViewController = ShellSplitViewController(model: model)
        // The panes have no preferred size, so assigning the controller
        // shrinks the window to its minimum; restore the default first.
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.delegate = self
        // A live light/dark switch, from the system or from Settings, has to
        // reach the editor's highlight colours and the preview's CSS too; the
        // storyboard window does this from MainWindowController.
        appearanceObservation = window.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.appearanceDidChange() }
        }
        if !window.setFrameUsingName("MiaoYanShellWindow") {
            window.center()
        }
        window.setFrameAutosaveName("MiaoYanShellWindow")
        applyWindowLevel()
        windowLevelObserver = NotificationCenter.default.addObserver(
            forName: .alwaysOnTopChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyWindowLevel() }
        }
        KeyboardShortcuts.onKeyUp(for: .activateWindow) { [weak self] in
            self?.toggleFrontmost()
        }
        observePresentation()
        retargetMainMenu()
        model.onFoldersChanged = { [weak self] in self?.fsManager?.restart() }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .editorSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.model.applyEditorSettings() }
        }
        fsManager = FileSystemEventManager(storage: AppEnvironment.current.storage, delegate: self)
        fsManager?.start()
        model.editor.onWillSave = { [weak self] in self?.blockFSUpdates() }
        singleModeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.model.isSingleMode, event.window === self.window,
                event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
                event.charactersIgnoringModifiers?.lowercased() == "w"
            else { return event }
            self.model.closeSingle()
            return nil
        }
    }

    /// Command-Shift-W leaves single-file mode, as in the storyboard window.
    private var singleModeMonitor: Any?

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Menu commands

    /// The storyboard menu sends many commands to stand-in `ViewController`
    /// and `EditTextView` objects that forward to the storyboard window, which
    /// the shell does not have. Pointing those items at the first responder
    /// lets the real editor take its formatting commands and this controller
    /// take the rest; items nobody answers are disabled by AppKit.
    private func retargetMainMenu() {
        // Folder items go to the storyboard sidebar's stand-ins and share
        // selectors with note items (`renameMenu:`), so they get folder
        // actions of their own here.
        let folderActions: [Selector: Selector] = [
            Selector(("renameMenu:")): #selector(renameFolderMenu(_:)),
            Selector(("revealInFinder:")): #selector(revealFolderMenu(_:)),
            Selector(("deleteMenu:")): #selector(deleteFolderMenu(_:)),
            Selector(("add:")): #selector(newFolderMenu(_:)),
            Selector(("addProject:")): #selector(newFolderMenu(_:)),
            Selector(("newSubfolder:")): #selector(newFolderMenu(_:)),
        ]
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if item.target is SidebarProjectView || item.target is SidebarCellView,
                    let action = item.action, let folderAction = folderActions[action]
                {
                    item.target = self
                    item.action = folderAction
                } else if item.target is ViewController || item.target is EditTextView {
                    item.target = nil
                }
                if let submenu = item.submenu { walk(submenu) }
            }
        }
        if let menu = NSApp.mainMenu { walk(menu) }
    }

    // MARK: Open and import

    /// File ▸ Open: one file or folder on its own, until Command-Shift-W.
    @IBAction func singleOpen(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = panel.urls.first else { return }
            self?.model.openSingle(url, siblingFiles: AppDelegate.siblingNoteFiles(of: url))
        }
    }

    /// File ▸ Import: Markdown files, or every note inside picked folders,
    /// copied into the main folder.
    @IBAction func importFiles(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.message = I18n.str("Select Markdown files or folders to import")
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK else { return }
            let picked = panel.urls
            let extensions = AppEnvironment.current.storage.allowedExtensions
            // A picked folder can be huge; scan it off the main thread.
            Task.detached(priority: .userInitiated) {
                let files = ViewController.collectImportableFiles(from: picked, allowedExtensions: extensions)
                await MainActor.run {
                    guard let self else { return }
                    guard !files.isEmpty else {
                        self.model.host?.toast(message: I18n.str("No importable Markdown files found~"), style: .failure)
                        return
                    }
                    self.model.importNotes(files)
                }
            }
        }
    }

    // MARK: Folders

    @IBAction func newFolderMenu(_ sender: Any?) { model.promptNewFolder() }

    @IBAction func renameFolderMenu(_ sender: Any?) {
        model.renamingFolderURL = model.selectedFolder?.url
    }

    @IBAction func revealFolderMenu(_ sender: Any?) {
        guard let folder = model.selectedFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder.url])
    }

    @IBAction func deleteFolderMenu(_ sender: Any?) {
        guard let folder = model.selectedFolder else { return }
        model.confirmDeleteFolder(folder)
    }

    /// File ▸ Move: the folders as a menu at the pointer.
    @IBAction func moveMenu(_ sender: Any?) {
        guard let note = model.selectedNote, let window, let view = window.contentView else { return }
        let menu = NSMenu()
        for folder in model.folders where folder != note.project {
            let item = NSMenuItem(title: folder.label, action: #selector(moveToFolder(_:)), keyEquivalent: "")
            item.representedObject = folder
            item.target = self
            menu.addItem(item)
        }
        let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        menu.popUp(positioning: nil, at: point, in: view)
    }

    @objc private func moveToFolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? Project, let note = model.selectedNote else { return }
        model.move([note], to: folder)
    }

    @IBAction func toggleSidebarPanel(_ sender: Any?) { model.toggleSidebar() }
    @IBAction func toggleNoteList(_ sender: Any?) { model.toggleNoteList() }
    @IBAction func togglePreview(_ sender: Any?) { model.togglePreview() }
    @IBAction func toggleSplitMode(_ sender: Any?) { model.toggleSplit() }
    @IBAction func togglePresentation(_ sender: Any?) { model.setPresenting(!model.isPresenting) }
    @IBAction func toggleMagicPPT(_ sender: Any?) { model.setPresenting(!model.isPresenting, ppt: true) }
    @IBAction func toggleTOC(_ sender: Any?) { model.preview?.toggleTOC() }
    @IBAction func formatText(_ sender: Any?) { model.format() }
    @IBAction func cleanTypography(_ sender: Any?) { model.cleanTypography() }
    @IBAction func fileMenuNewNote(_ sender: Any?) { model.createNote() }
    @IBAction func deleteNote(_ sender: Any?) { model.deleteSelectedNote() }
    @IBAction func renameMenu(_ sender: Any?) { model.isRenaming = model.selectedNote != nil }
    @IBAction func searchAndCreate(_ sender: Any?) { model.isSearchOpen = true }

    @IBAction func pinMenu(_ sender: Any?) {
        guard let note = model.selectedNote else { return }
        model.togglePin(note)
    }

    @IBAction func finderMenu(_ sender: Any?) {
        guard let note = model.selectedNote else { return }
        NSWorkspace.shared.activateFileViewerSelecting([note.url])
    }

    /// Find, find and replace, next and previous, by the storyboard window's
    /// rules: the preview's own search while the preview is showing, the
    /// editor's find bar otherwise. Replace needs the editor, since the
    /// preview's buffer may belong to another note in the shell.
    @IBAction func textFinder(_ sender: NSMenuItem) {
        let editor = model.editor.textView
        if model.editorMode == .preview || model.isPresenting {
            guard let preview = model.preview else { return }
            if sender.tag == NSFindPanelAction.next.rawValue {
                preview.findNext()
            } else if sender.tag == NSFindPanelAction.previous.rawValue {
                preview.findPrevious()
            } else {
                preview.showSearchBar(mode: .find)
            }
            return
        }
        if let action = NSFindPanelAction(rawValue: UInt(sender.tag)) {
            switch action {
            case .next, .previous:
                if !editor.isSearchBarVisible {
                    editor.showSearchBar(prefilledText: editor.currentSearchQuery)
                }
                action == .next ? editor.findNext() : editor.findPrevious()
                return
            case .setFindString:
                editor.useSelectionForFind()
                return
            default:
                break
            }
        }
        if let action = NSTextFinder.Action(rawValue: sender.tag) {
            switch action {
            case .showFindInterface:
                editor.showSearchBar(prefilledText: nil, mode: .find)
                return
            case .showReplaceInterface:
                editor.showSearchBar(prefilledText: nil, mode: .replace)
                return
            case .hideFindInterface:
                editor.hideSearchBar()
                return
            default:
                break
            }
        }
        editor.performTextFinderAction(sender)
    }

    @IBAction func showVersionHistory(_ sender: Any?) { model.showVersionHistory() }

    /// Words, dates and backlinks, under the note's title.
    @IBAction func showInfo(_ sender: Any?) {
        guard let note = model.selectedNote,
            let split = window?.contentViewController as? NSSplitViewController,
            let detail = split.splitViewItems.last?.viewController.view
        else { return }
        let content = ContentViewController()
        content.note = note
        infoPopover.contentViewController = content
        // The hosting view is flipped: this is the title line at the top.
        let anchor = NSRect(x: ShellStyle.noteTextInset, y: 0, width: 1, height: ShellStyle.headerHeight - 10)
        infoPopover.show(relativeTo: anchor, of: detail, preferredEdge: .maxY)
    }

    private lazy var infoPopover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .semitransient
        return popover
    }()

    /// The chosen folder, or the library, in the preferred terminal.
    @IBAction func openInTerminal(_ sender: Any?) {
        let url = model.selectedFolder?.url ?? UserDefaultsManagement.storageUrl
        guard let url else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", ViewController.preferredTerminalBundleID(), url.path]
        do {
            try process.run()
        } catch {
            AppDelegate.trackError(error, context: "ShellWindowController.openInTerminal")
        }
    }

    @IBAction func cleanUnusedAttachments(_ sender: Any?) { model.cleanUnusedAttachments() }
    @IBAction func exportMiaoYanPPT(_ sender: Any?) { model.export(.ppt) }
    @IBAction func zoomInFontSize(_ sender: Any?) { model.adjustFontSize(by: 1) }
    @IBAction func zoomOutFontSize(_ sender: Any?) { model.adjustFontSize(by: -1) }
    @IBAction func resetFontSize(_ sender: Any?) { model.adjustFontSize(by: nil) }
    @IBAction func duplicate(_ sender: Any?) { model.duplicateSelectedNote() }
    @IBAction func reloadCurrentNote(_ sender: Any?) { model.reloadSelectedNote() }
    @IBAction func copyURL(_ sender: Any?) { model.copyNoteURL() }
    @IBAction func copyPath(_ sender: Any?) { model.copyNotePath() }

    /// Edit ▸ Copy is `noteCopy:`, which the storyboard window routes by
    /// focus: the editor copies its selection, the preview its selection,
    /// the note list the whole note.
    @IBAction func noteCopy(_ sender: Any?) {
        guard let responder = window?.firstResponder else { return }
        let editor = model.editor.textView
        if responder === editor {
            editor.copy(sender)
        } else if let preview = model.preview, let view = responder as? NSView,
            view === preview || view.isDescendant(of: preview)
        {
            preview.copySelectionToPasteboard()
        } else if let note = model.selectedNote {
            note.ensureContentLoaded()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(note.content.string, forType: .string)
        }
    }

    private var settingsObserver: NSObjectProtocol?

    // MARK: Export

    @IBAction func exportPdf(_ sender: Any?) { model.export(.pdf) }
    @IBAction func exportImage(_ sender: Any?) { model.export(.image) }
    @IBAction func exportHtml(_ sender: Any?) { model.export(.html) }

    /// File ▸ Export: the three formats as a menu at the pointer, the way the
    /// storyboard window pops its note menu's Export submenu.
    @IBAction func exportMenu(_ sender: Any?) {
        guard model.selectedNote != nil, let window, let view = window.contentView else { return }
        let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        Self.exportFormatsMenu().popUp(positioning: nil, at: point, in: view)
    }

    static func exportFormatsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "PDF", action: #selector(exportPdf(_:)), keyEquivalent: "")
        menu.addItem(withTitle: I18n.str("Image"), action: #selector(exportImage(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "HTML", action: #selector(exportHtml(_:)), keyEquivalent: "")
        return menu
    }

    @IBAction func sortBy(_ sender: NSMenuItem) {
        guard let id = sender.identifier, let sort = SortBy(rawValue: String(id.rawValue.dropFirst(3))) else { return }
        model.setSort(sort)
    }

    @IBAction func sortDirectionBy(_ sender: NSMenuItem) {
        model.setSortDescending(sender.identifier?.rawValue == "Descending")
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let hasNote = model.selectedNote != nil
        switch menuItem.action {
        case #selector(sortBy(_:)):
            menuItem.state = menuItem.identifier?.rawValue == "SB.\(UserDefaultsManagement.sort.rawValue)" ? .on : .off
            return true
        case #selector(sortDirectionBy(_:)):
            let descending = menuItem.identifier?.rawValue == "Descending"
            menuItem.state = descending == UserDefaultsManagement.sortDirection ? .on : .off
            return true
        case #selector(togglePreview(_:)):
            menuItem.state = model.editorMode == .preview ? .on : .off
            return hasNote && !model.isPresenting
        case #selector(toggleSplitMode(_:)):
            menuItem.state = model.editorMode == .split ? .on : .off
            return hasNote && !model.isPresenting
        case #selector(togglePresentation(_:)):
            menuItem.state = model.isPresenting && !model.isPPT ? .on : .off
            return hasNote && !model.isPPT
        case #selector(toggleMagicPPT(_:)):
            menuItem.state = model.isPPT ? .on : .off
            return hasNote && (!model.isPresenting || model.isPPT)
        case #selector(toggleTOC(_:)):
            return hasNote && model.editorMode != .edit
        case #selector(formatText(_:)), #selector(cleanTypography(_:)):
            return hasNote && model.editorMode != .preview && !model.isPresenting
        case #selector(deleteNote(_:)):
            return hasNote && model.selectedNote?.isTrash() == false && !model.isPresenting
        case #selector(duplicate(_:)):
            return hasNote && model.selectedNote?.isTrash() == false && !model.isPresenting
        case #selector(reloadCurrentNote(_:)), #selector(copyURL(_:)), #selector(copyPath(_:)), #selector(noteCopy(_:)):
            return hasNote
        case #selector(exportMiaoYanPPT(_:)):
            return hasNote && !model.isExporting && (!model.isPresenting || model.isPPT)
        case #selector(showInfo(_:)):
            return hasNote && !model.isPresenting
        case #selector(showVersionHistory(_:)):
            return hasNote && model.selectedNote?.isTrash() == false && !model.isPresenting
        case #selector(textFinder(_:)):
            return hasNote
        case #selector(renameFolderMenu(_:)), #selector(revealFolderMenu(_:)):
            return model.selectedFolder != nil
        case #selector(deleteFolderMenu(_:)):
            return model.selectedFolder.map { !$0.isDefault && !$0.isRoot } ?? false
        case #selector(moveMenu(_:)):
            return hasNote && model.selectedNote?.isTrash() == false && !model.isPresenting
        case #selector(exportPdf(_:)), #selector(exportImage(_:)), #selector(exportHtml(_:)), #selector(exportMenu(_:)):
            return hasNote && !model.isExporting
        case #selector(renameMenu(_:)), #selector(pinMenu(_:)), #selector(finderMenu(_:)):
            return hasNote && !model.isPresenting
        default:
            return true
        }
    }

    // MARK: - Disk changes

    private var fsManager: FileSystemEventManager?
    private var fsResumeTimer: Timer?

    /// The storyboard window's rule: while an edit is being saved, ignore disk
    /// events briefly so the save itself does not reload the note under the
    /// cursor (destructive mid IME composition), then re-check once.
    private func blockFSUpdates() {
        AppEnvironment.current.userData.fsUpdatesDisabled = true
        fsResumeTimer?.invalidate()
        fsResumeTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                AppEnvironment.current.userData.fsUpdatesDisabled = false
                if let note = EditTextView.note {
                    self?.fsManager?.recheckNote(note)
                }
            }
        }
    }

    // MARK: - Window level and activation

    private var windowLevelObserver: NSObjectProtocol?

    /// View ▸ Always on Top, applied the way `MainWindowController` does.
    private func applyWindowLevel() {
        window?.level = UserDefaultsManagement.alwaysOnTop ? .floating : .normal
    }

    /// The activate shortcut and Window ▸ Active Window: hide MiaoYan when it
    /// is already in front, otherwise bring this window forward.
    func toggleFrontmost() {
        guard let window else { return }
        if NSApp.isActive, !NSApp.isHidden, !window.isMiniaturized {
            NSApp.hide(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Presentation

    private var escapeMonitor: Any?

    /// Presentation fills the screen; leaving full screen by any route, or
    /// pressing Escape, ends it.
    func observePresentation() {
        let presenting = withObservationTracking {
            model.isPresenting
        } onChange: { [weak self] in
            Task { @MainActor in self?.observePresentation() }
        }
        guard let window else { return }
        let isFullScreen = window.styleMask.contains(.fullScreen)
        if presenting {
            if !isFullScreen { window.toggleFullScreen(nil) }
            escapeMonitor =
                escapeMonitor
                ?? NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard event.keyCode == 53, let self, self.model.isPresenting else { return event }
                    self.model.setPresenting(false)
                    return nil
                }
        } else {
            if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
            escapeMonitor = nil
            if isFullScreen, didEnterFullScreenForPresentation {
                isLeavingFullScreenForPresentation = true
                window.toggleFullScreen(nil)
            }
        }
    }

    private var didEnterFullScreenForPresentation = false
    /// Set while this controller itself leaves full screen at the end of a
    /// presentation, so the exit callback does not end a presentation that
    /// was started again before the animation finished.
    private var isLeavingFullScreenForPresentation = false

    func windowDidEnterFullScreen(_ notification: Notification) {
        didEnterFullScreenForPresentation = model.isPresenting
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        didEnterFullScreenForPresentation = false
        if isLeavingFullScreenForPresentation {
            isLeavingFullScreenForPresentation = false
            // A presentation started again during the exit animation wants
            // full screen back.
            if model.isPresenting { window?.toggleFullScreen(nil) }
            return
        }
        model.setPresenting(false)
    }

    func windowWillClose(_ notification: Notification) {
        model.setPresenting(false)
        flushEdits()
    }

    func windowDidResignKey(_ notification: Notification) {
        flushEdits()
    }

    private func appearanceDidChange() {
        guard let window else { return }
        AppEnvironment.current.userData.isDark = window.effectiveAppearance.isDark
        NotesTextProcessor.hl = nil
        if let note = model.editor.textView.storageNote {
            NotesTextProcessor.highlight(note: note)
            model.editor.reload(note)
        }
        model.preview?.updateAppearance()
    }

    /// Writes the editor's text and every debounced save now. A save waits
    /// 1.5s after the last key, so quitting, closing the window or switching
    /// apps inside that window would otherwise lose the last edits; the
    /// storyboard window does the same through its ViewController.
    func flushEdits() {
        let editor = model.editor.textView
        if let owner = editor.storageNote {
            editor.saveTextStorageContent(to: owner)
        }
        AppEnvironment.current.storage.flushPendingSaves()
    }
}

@available(macOS 14, *)
extension ShellWindowController: FileSystemEventHost {
    func fsReloadList(selecting note: Note?, completion: (@MainActor @Sendable () -> Void)?) {
        model.reload()
        model.refreshNow(selecting: note?.url) { completion?() }
    }

    func fsInsert(_ note: Note) { model.refreshNow() }
    func fsReloadSidebar() { model.reload() }

    func fsSelectFirstNote() {
        model.selectedNoteURL = model.notes.first?.url
    }

    func fsRemove(_ notes: [Note]) { model.refreshNow() }

    func fsReload(_ note: Note) {
        model.noteChangedOnDisk(note)
    }

    func fsRefillEditor() {
        guard let note = EditTextView.note else { return }
        model.editor.reload(note)
    }

    var fsEditorBuffer: (owner: Note?, text: String)? {
        (model.editor.textView.storageNote, model.editor.textView.string)
    }

    func fsToast(_ message: String, style: ToastStyle) {
        model.host?.toast(message: message, style: style)
    }
}

/// Folders, notes and the open note side by side. The split stays AppKit so
/// the panes keep their widths when the window resizes and the dividers are
/// remembered; each pane is SwiftUI. Plain split items, not the sidebar kind,
/// so no translucent material appears behind the folders.
@available(macOS 14, *)
final class ShellSplitViewController: NSSplitViewController {
    private let model: ShellModel
    var shellModel: ShellModel { model }

    init(model: ShellModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        splitView = ShellSplitView()
        super.loadView()
    }

    override func viewDidLoad() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let sidebar = NSSplitViewItem(viewController: Self.host(ShellSidebar(model: model)))
        sidebar.minimumThickness = 150
        sidebar.maximumThickness = 280
        sidebar.canCollapse = true
        sidebar.holdingPriority = NSLayoutConstraint.Priority(260)

        let list = NSSplitViewItem(viewController: Self.host(ShellNoteList(model: model)))
        list.canCollapse = true
        list.minimumThickness = Theme.Metrics.noteListMinimumWidth
        list.maximumThickness = 420
        list.holdingPriority = NSLayoutConstraint.Priority(255)

        let detail = NSSplitViewItem(viewController: Self.host(ShellDetail(model: model)))
        detail.minimumThickness = 320
        detail.holdingPriority = NSLayoutConstraint.Priority(240)

        for item in [sidebar, list, detail] {
            addSplitViewItem(item)
        }
        splitView.autosaveName = "MiaoYanShellSplit"
        super.viewDidLoad()
        model.host = self
        ExportHosts.shell = self
        observeLayout()
    }

    /// Collapses the folders and the list as the layout button cycles.
    private func observeLayout() {
        let layout = withObservationTracking {
            model.layout
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeLayout() }
        }
        let items = splitViewItems
        guard items.count == 3 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            items[0].animator().isCollapsed = layout != .all
            items[1].animator().isCollapsed = layout == .noteOnly
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !hasAppliedDefaultWidths else { return }
        hasAppliedDefaultWidths = true
        // First launch only: the autosaved positions win afterwards.
        if UserDefaults.standard.object(forKey: "NSSplitView Subview Frames MiaoYanShellSplit") == nil {
            splitView.setPosition(180, ofDividerAt: 0)
            splitView.setPosition(180 + 1 + 280, ofDividerAt: 1)
        }
    }

    private var hasAppliedDefaultWidths = false

    /// Without clearing `sizingOptions` the hosting controllers would size
    /// the panes to their SwiftUI content instead of leaving that to the split.
    private static func host(_ view: some View) -> NSViewController {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        return controller
    }
}

/// Every column shares one tone, so each divider is a hairline.
@available(macOS 14, *)
final class ShellSplitView: NSSplitView {
    override func drawDivider(in rect: NSRect) {
        ShellPalette.background.setFill()
        rect.fill()
        ShellPalette.hairline.setFill()
        rect.fill(using: .sourceOver)
    }
}

/// Exports report here: the open note, its title, progress toasts, and the
/// mode to return to once the file is written.
@available(macOS 14, *)
extension ShellSplitViewController: ExportHost {
    var exportNote: Note? { shellModel.selectedNote }
    var exportTitle: String { shellModel.selectedNote?.getTitleWithoutLabel() ?? "" }

    func toastExport(status: Bool) {
        if status {
            toast(message: I18n.str("Saved to Downloads folder~"), style: .success)
        } else {
            toast(message: I18n.str("Export failed"), style: .failure)
        }
        shellModel.finishExport()
    }

    func finishPPTExport() { shellModel.finishPPTExport() }
}
