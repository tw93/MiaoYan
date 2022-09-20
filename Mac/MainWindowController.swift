import AppKit

class MainWindowController: NSWindowController, NSWindowDelegate {
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
    }
}
