import AppKit

@MainActor
class MainWindowController: NSWindowController, NSWindowDelegate, NSWindowRestoration {
    let notesListUndoManager = UndoManager()
    var editorUndoManager = UndoManager()
    private var isObservingAppearance = false
    /// Last time `windowDidResignKey` flushed pending saves. Used to throttle
    /// the lifecycle flush so transient resign events (Spotlight, system
    /// permission dialogs, NSAlert, etc.) don't trigger a synchronous disk
    /// write storm against an iCloud-backed notes folder.
    private var lastResignKeyFlushAt: TimeInterval = 0
    private static let resignKeyFlushMinInterval: TimeInterval = 2.0

    override func windowDidLoad() {
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.mainWindowController = self

        window?.isMovableByWindowBackground = true
        window?.hidesOnDeactivate = false
        window?.titleVisibility = .hidden
        window?.titlebarAppearsTransparent = true
        windowFrameAutosaveName = "myMainWindow"
        window?.restorationClass = MainWindowController.self
        window?.delegate = self

        updateAlwaysOnTopState()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateAlwaysOnTopState),
            name: .alwaysOnTopChanged,
            object: nil
        )

        applyMiaoYanAppearance()
        observeAppearanceChanges()
    }

    @objc private func updateAlwaysOnTopState() {
        window?.level = UserDefaultsManagement.alwaysOnTop ? .floating : .normal
    }

    private func observeAppearanceChanges() {
        guard !isObservingAppearance, let contentView = window?.contentView else {
            return
        }

        contentView.addObserver(
            self,
            forKeyPath: "effectiveAppearance",
            options: [.new],
            context: nil
        )
        isObservingAppearance = true
    }

    // swiftlint:disable:next block_based_kvo
    nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "effectiveAppearance" {
            Task { @MainActor in
                handleAppearanceChange()
            }
        }
    }

    private func handleAppearanceChange() {
        guard UserDefaultsManagement.appearanceType == .System else { return }

        if let effectiveAppearance = window?.effectiveAppearance {
            UserDataService.instance.isDark = effectiveAppearance.isDark
        }

        applyMiaoYanAppearance()

        if let vc = AppContext.shared.viewController {
            vc.editArea.applySystemAppearance()
            vc.editArea.markdownView?.updateAppearance()
            vc.applyModernChromeStyling()
            vc.updateToolbarButtonTints()

            // Save current selection before refreshing rows
            let selectedNotesRow = vc.notesTableView.selectedRow
            let selectedSidebarRow = vc.storageOutlineView.selectedRow

            // Refresh existing rows instead of reloading to preserve selection
            vc.notesTableView.enumerateAvailableRowViews { rowView, _ in
                rowView.needsDisplay = true
            }

            vc.storageOutlineView.enumerateAvailableRowViews { rowView, _ in
                rowView.needsDisplay = true
            }

            // Restore selection after refreshing
            if selectedNotesRow >= 0 && selectedNotesRow < vc.notesTableView.numberOfRows {
                vc.notesTableView.selectRowIndexes([selectedNotesRow], byExtendingSelection: false)
            }

            if selectedSidebarRow >= 0 && selectedSidebarRow < vc.storageOutlineView.numberOfRows {
                vc.storageOutlineView.selectRowIndexes([selectedSidebarRow], byExtendingSelection: false)
            }
        }
    }

    func windowDidResize(_ notification: Notification) {
        refreshEditArea()
    }

    func makeNew() {
        applyMiaoYanAppearance()

        // Check if window needs to be shown (and wasn't just minimized)
        // We use a fade-in effect to mask any potential white flashes during initial render
        let needsFadeIn = !(window?.isVisible ?? false) && !(window?.isMiniaturized ?? false)

        if needsFadeIn {
            window?.alphaValue = 0
        }

        window?.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)

        refreshEditArea(focusSearch: true)

        if needsFadeIn {
            // Delay the fade-in just enough to ensure the view hierarchy and transparent backgrounds
            // have completely repainted. This ensures "start with nothing, then fade in after loaded".
            revealWindowWhenReady()
        }
    }

    func refreshEditArea(focusSearch: Bool = false) {
        guard let vc = AppContext.shared.viewController else { return }
        vc.editArea.updateTextContainerInset()

        // Update WebView frame if in preview mode
        if let markdownView = vc.editArea.markdownView, !markdownView.isHidden {
            let newFrame = vc.editAreaScroll.bounds
            if markdownView.frame.size != newFrame.size {
                markdownView.frame = newFrame
            }
        }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        guard let fr = window.firstResponder else {
            return notesListUndoManager
        }

        if fr.isKind(of: NotesTableView.self) {
            return notesListUndoManager
        }

        if fr.isKind(of: EditTextView.self) {
            guard let vc = AppContext.shared.viewController, let ev = vc.editArea, ev.isEditable else { return notesListUndoManager }
            return editorUndoManager
        }

        return notesListUndoManager
    }

    // MARK: - Window Reveal Animation
    func revealWindowWhenReady() {
        guard let window = window, window.alphaValue < 1 else { return }

        // Wait slightly to ensure WebView layout is finalized (run loop cycle)
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                window.animator().alphaValue = 1
            }
        }
    }

    public static func shared() -> NSWindow? {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            return appDelegate.mainWindowController?.window
        }

        return nil
    }

    /// Closure scheduled by mode-transition code that needs to run only
    /// after macOS finishes its fullscreen exit animation (~700ms in
    /// practice). Replaces the previous 0.15s asyncAfter heuristic so layout
    /// restoration lands in the same frame the fullscreen transition ends.
    var pendingPostFullScreenAction: (() -> Void)?

    func windowWillEnterFullScreen(_ notification: Notification) {
        UserDefaultsManagement.isWillFullScreen = true
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        UserDefaultsManagement.isWillFullScreen = false
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        AppContext.shared.sessionState.fullScreen = true
        // Drop anything queued from before we entered fullscreen; it would
        // run against the wrong layout.
        pendingPostFullScreenAction = nil
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        AppContext.shared.sessionState.fullScreen = false
        let pending = pendingPostFullScreenAction
        pendingPostFullScreenAction = nil
        pending?()
        // Auto-exit presentation modes when exiting full screen to prevent UI inconsistencies
        if let vc = AppContext.shared.viewController {
            if vc.sessionPresentationMode {
                vc.disablePresentation()
            } else if vc.sessionMagicPPTMode {
                vc.disableMiaoYanPPT()
            }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        applyMiaoYanAppearance()

        // Ensure WebView background is transparent to avoid white flashes on reactivation
        if let vc = AppContext.shared.viewController,
            let markdownView = vc.editArea.markdownView,
            !markdownView.isHidden
        {
            markdownView.setValue(false, forKey: "drawsBackground")
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Switching to another app or window can be the last interaction
        // before a kill / power loss. Drain the 1.5s debounce queue so the
        // current edits are durable on disk before we lose focus.
        //
        // But: macOS fires resign-key for transient events too (Spotlight,
        // permission prompts, NSOpenPanel, system notifications stealing
        // focus). Without a throttle we'd issue a synchronous disk write
        // every time, which is especially painful on iCloud-backed notes
        // (each write nudges the sync engine). Skip if we already flushed
        // very recently, and only push the active note rather than scanning
        // the entire noteList.
        guard AppContext.shared.viewController != nil else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastResignKeyFlushAt < Self.resignKeyFlushMinInterval {
            return
        }
        lastResignKeyFlushAt = now

        guard let activeNote = EditTextView.note else { return }
        // hasPendingSave means textDidChange already pushed the latest editor
        // contents into note.content and queued a debounced write. Skipping
        // when it's false avoids gratuitous IO when the user just lost focus
        // without touching anything.
        guard activeNote.hasPendingSave else { return }
        activeNote.flushPendingSave()
    }

    func windowWillClose(_ notification: Notification) {
        if isObservingAppearance, let contentView = window?.contentView {
            contentView.removeObserver(self, forKeyPath: "effectiveAppearance")
            isObservingAppearance = false
        }
        NotificationCenter.default.removeObserver(self, name: .alwaysOnTopChanged, object: nil)
        if let vc = AppContext.shared.viewController {
            vc.persistCurrentViewState()
            if let activeNote = EditTextView.note {
                vc.editArea.saveTextStorageContent(to: activeNote)
            }
            vc.storage.flushPendingSaves()
        }
    }

    func applyMiaoYanAppearance() {
        guard let window = window else { return }

        let targetAppearance: NSAppearance?
        let backgroundColor: NSColor

        if UserDefaultsManagement.appearanceType != .Custom {
            switch UserDefaultsManagement.appearanceType {
            case .Light:
                targetAppearance = NSAppearance(named: .aqua)
                backgroundColor = Theme.windowChromeBackgroundColor
            case .Dark:
                targetAppearance = NSAppearance(named: .darkAqua)
                backgroundColor = Theme.windowChromeBackgroundColor
            case .System:
                // In System mode, set appearance to nil to follow system
                targetAppearance = nil
                backgroundColor = Theme.windowChromeBackgroundColor
            default:
                targetAppearance = nil
                backgroundColor = Theme.windowChromeBackgroundColor
            }
        } else {
            targetAppearance = nil
            backgroundColor = UserDefaultsManagement.bgColor
        }

        // Only update if appearance actually changed
        let currentAppearance = window.appearance
        let needsAppearanceUpdate = (targetAppearance?.name != currentAppearance?.name) || (targetAppearance == nil && currentAppearance != nil) || (targetAppearance != nil && currentAppearance == nil)

        if needsAppearanceUpdate {
            // Set window appearance
            window.appearance = targetAppearance
            window.contentView?.appearance = targetAppearance
        }

        window.isOpaque = !Theme.usesModernSystemChrome

        // Background. window.backgroundColor holds a dynamic NSColor, so it
        // only needs assigning when the color identity actually changes. The
        // contentView's layer, however, holds a *resolved* cgColor snapshot
        // that does not auto-adapt, so it must be re-resolved against the
        // current appearance on every call. In modern chrome all modes use the
        // same dynamic .windowBackgroundColor, so the old equality gate was
        // always false on a light/dark switch and left the previous
        // appearance's color baked into the layer until the next relaunch,
        // showing as a stale light strip under a dark window (and vice versa).
        if window.backgroundColor != backgroundColor {
            window.backgroundColor = backgroundColor
        }
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            let resolvedBackground = backgroundColor.resolvedColor(for: contentView.effectiveAppearance)
            contentView.layer?.backgroundColor = resolvedBackground.cgColor
            contentView.needsDisplay = true
            contentView.subviews.forEach { $0.needsDisplay = true }
        }

        if let vc = AppContext.shared.viewController {
            if let sidebarSplit = vc.sidebarSplitView as? SidebarSplitView {
                sidebarSplit.displayIfNeeded()
            }
            if let editorSplit = vc.splitView {
                editorSplit.displayIfNeeded()
            }
            // Re-clamp the sidebar column to the pane after the appearance
            // change. The column has resizingMask = .autoresizingMask, so the
            // relayout triggered by switching light/dark can leave it (and the
            // outline's document frame) wider than the clip view. Every other
            // relayout path calls updateSidebarColumnWidth(); the appearance
            // path is the one that skipped it, which let the sidebar content
            // stay horizontally scrollable until the next resize or relaunch.
            // Deferred so the switch's own layout pass settles first.
            DispatchQueue.main.async {
                vc.updateSidebarColumnWidth()
            }
        }
    }

    // MARK: - NSWindowRestoration
    static func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier, state: NSCoder, completionHandler: @escaping (NSWindow?, Error?) -> Void) {
        if identifier.rawValue == "myMainWindow" {
            let storyboard = NSStoryboard(name: "Main", bundle: nil)
            if let mainWC = storyboard.instantiateController(withIdentifier: "MainWindowController") as? MainWindowController {
                completionHandler(mainWC.window, nil)
                return
            }
        }
        completionHandler(nil, nil)
    }

}
