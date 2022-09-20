import Cocoa

class PrefsWindowController: NSWindowController, NSWindowDelegate {
    override func windowDidLoad() {
        super.windowDidLoad()
        window?.delegate = self
        window?.title = "Preferences"
    }
}
