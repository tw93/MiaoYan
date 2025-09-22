import AppKit

@MainActor
class MainWindowController: NSWindowController, NSWindowDelegate, NSWindowRestoration {
    let notesListUndoManager = UndoManager()
    var editorUndoManager = UndoManager()

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
            let isDarkTheme: Bool
            switch UserDefaultsManagement.appearanceType {
            case .Light:
                isDarkTheme = false
            case .Dark:
                isDarkTheme = true
            case .System:
                isDarkTheme = UserDataService.instance.isDark
            default:
                isDarkTheme = UserDataService.instance.isDark
            }

            if isDarkTheme {
                targetAppearance = NSAppearance(named: .darkAqua)
                backgroundColor = Theme.backgroundColor
            } else {
                targetAppearance = NSAppearance(named: .aqua)
                backgroundColor = Theme.backgroundColor
            }
        } else {
            targetAppearance = nil
            backgroundColor = UserDefaultsManagement.bgColor
        }

        if let appearance = targetAppearance {
            window.appearance = appearance
            window.contentView?.appearance = appearance
        }
        window.backgroundColor = backgroundColor

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            let effectiveAppearance = window.appearance ?? contentView.effectiveAppearance
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
