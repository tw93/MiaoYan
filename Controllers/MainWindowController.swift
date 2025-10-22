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

        if UserDefaultsManagement.alwaysOnTop {
            window?.level = .floating
        } else {
            window?.level = .normal
        }

        applyMiaoYanAppearance()
        observeAppearanceChanges()
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
        }
    }

    func windowDidResize(_ notification: Notification) {
        refreshEditArea()
    }

    func makeNew() {
        applyMiaoYanAppearance()
        window?.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
        refreshEditArea(focusSearch: true)
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

        // Set window appearance
        window.appearance = targetAppearance
        window.contentView?.appearance = targetAppearance
        window.backgroundColor = backgroundColor

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            let effectiveAppearance = contentView.effectiveAppearance
            let resolvedBackground = backgroundColor.resolvedColor(for: effectiveAppearance)
            contentView.layer?.backgroundColor = resolvedBackground.cgColor
            contentView.needsDisplay = true
        }

        window.contentView?.subviews.forEach { $0.needsDisplay = true }

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
