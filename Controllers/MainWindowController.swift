import AppKit

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

        // Apply always-on-top preference based on user settings
        if UserDefaultsManagement.alwaysOnTop {
            window?.level = .floating
        } else {
            window?.level = .normal
        }

        applyMiaoYanAppearance()

        // 提前刷新分割线颜色，避免窗口首次显示时颜色闪烁
        if let vc = ViewController.shared() {
            vc.updateDividers()
        }
    }

    func windowDidResize(_ notification: Notification) {
        refreshEditArea()
    }

    func makeNew() {
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

    func applyMiaoYanAppearance() {
        guard let window = window else { return }

        // Apply MiaoYan's custom appearance settings, overriding system appearance when needed
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
            // For custom themes, preserve user's background color without forcing system appearance
            targetAppearance = nil
            backgroundColor = UserDefaultsManagement.bgColor
        }

        // Apply appearance and background color immediately
        if let appearance = targetAppearance {
            window.appearance = appearance
        }
        window.backgroundColor = backgroundColor

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = backgroundColor.cgColor
        }

        DispatchQueue.main.async { [weak window] in
            guard
                let viewController = window?.contentViewController as? ViewController
            else {
                return
            }

            viewController.updateDividers()
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
