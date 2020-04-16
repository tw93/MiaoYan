import AppKit

class MainWindowController: NSWindowController, NSWindowDelegate {
    let notesListUndoManager = UndoManager()
    var editorUndoManager = UndoManager()
    
    override func windowDidLoad() {
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.mainWindowController = self

        self.window?.hidesOnDeactivate = UserDefaultsManagement.hideOnDeactivate
        self.window?.titleVisibility = .hidden
        self.window?.titlebarAppearsTransparent = true

        self.windowFrameAutosaveName = "myMainWindow"
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

        if vc.storageOutlineView.isFirstLaunch || focusSearch {
            vc.search.window?.makeFirstResponder(vc.search)
        } else {
            vc.focusEditArea()
        }

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

    func windowDidEnterFullScreen(_ notification: Notification) {
        UserDefaultsManagement.fullScreen = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        UserDefaultsManagement.fullScreen = false
    }
}
