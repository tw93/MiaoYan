import AppKit

@MainActor
class MainWindowController: NSWindowController, NSWindowDelegate, NSWindowRestoration {
    let notesListUndoManager = UndoManager()
    var editorUndoManager = UndoManager()
    private var isObservingAppearance = false

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

        if let vc = ViewController.shared() {
            vc.editArea.applySystemAppearance()
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

    nonisolated deinit {
        MainActor.assumeIsolated {
            if isObservingAppearance, let contentView = window?.contentView {
                contentView.removeObserver(self, forKeyPath: "effectiveAppearance")
                isObservingAppearance = false
            }
            NotificationCenter.default.removeObserver(self, name: .alwaysOnTopChanged, object: nil)
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
        guard let vc = ViewController.shared() else { return }
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
            guard let vc = ViewController.shared(), let ev = vc.editArea, ev.isEditable else { return notesListUndoManager }
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

    func windowWillEnterFullScreen(_ notification: Notification) {
        UserDefaultsManagement.isWillFullScreen = true
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        UserDefaultsManagement.isWillFullScreen = false
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        UserDefaultsManagement.fullScreen = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        UserDefaultsManagement.fullScreen = false
        // Auto-exit presentation modes when exiting full screen to prevent UI inconsistencies
        if let vc = ViewController.shared() {
            if UserDefaultsManagement.presentation {
                vc.disablePresentation()
            } else if UserDefaultsManagement.magicPPT {
                vc.disableMiaoYanPPT()
            }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        applyMiaoYanAppearance()

        // Ensure WebView background is transparent to avoid white flashes on reactivation
        if let vc = ViewController.shared(),
            let markdownView = vc.editArea.markdownView,
            !markdownView.isHidden
        {
            markdownView.setValue(false, forKey: "drawsBackground")
        }
    }

    func windowWillClose(_ notification: Notification) {
        ViewController.shared()?.persistCurrentViewState()
    }

    func applyMiaoYanAppearance() {
        guard let window = window else { return }

        let targetAppearance: NSAppearance?
        let backgroundColor: NSColor

        if UserDefaultsManagement.appearanceType != .Custom {
            switch UserDefaultsManagement.appearanceType {
            case .Light:
                targetAppearance = NSAppearance(named: .aqua)
                backgroundColor = Theme.backgroundColor
            case .Dark:
                targetAppearance = NSAppearance(named: .darkAqua)
                backgroundColor = Theme.backgroundColor
            case .System:
                // In System mode, set appearance to nil to follow system
                targetAppearance = nil
                backgroundColor = Theme.backgroundColor
            default:
                targetAppearance = nil
                backgroundColor = Theme.backgroundColor
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

        // Only update background if it changed
        if window.backgroundColor != backgroundColor {
            window.backgroundColor = backgroundColor

            if let contentView = window.contentView {
                contentView.wantsLayer = true
                let effectiveAppearance = contentView.effectiveAppearance
                let resolvedBackground = backgroundColor.resolvedColor(for: effectiveAppearance)
                contentView.layer?.backgroundColor = resolvedBackground.cgColor
                contentView.needsDisplay = true
            }

            window.contentView?.subviews.forEach { $0.needsDisplay = true }
        }

        if let vc = ViewController.shared() {
            if let sidebarSplit = vc.sidebarSplitView as? SidebarSplitView {
                sidebarSplit.displayIfNeeded()
            }
            if let editorSplit = vc.splitView {
                editorSplit.displayIfNeeded()
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
