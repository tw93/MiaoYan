import Cocoa

class AboutWindowController: NSWindowController, NSWindowDelegate {

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.delegate = self
        window?.title = "About"
    }
}
