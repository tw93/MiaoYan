import Cocoa

class PrefsWindowController: NSWindowController, NSWindowDelegate {

    override func windowDidLoad() {
        super.windowDidLoad()
        self.window?.delegate = self
        self.window?.title = "Preferences"
    }
}
