import Cocoa

@MainActor
class AboutWindowController: NSWindowController, NSWindowDelegate {
    override func windowDidLoad() {
        super.windowDidLoad()
        window?.delegate = self
        window?.title = I18n.str("About")
    }
}
