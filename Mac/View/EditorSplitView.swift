import Cocoa

class EditorSplitView: NSSplitView, NSSplitViewDelegate {
    public var shouldHideDivider = false

    override func draw(_ dirtyRect: NSRect) {
        delegate = self
        super.draw(dirtyRect)
    }

    override func minPossiblePositionOfDivider(at dividerIndex: Int) -> CGFloat { 0 }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        ViewController.shared()?.viewDidResize()
    }

    func splitViewWillResizeSubviews(_ notification: Notification) {
        if let vc = ViewController.shared() {
            vc.editArea.updateTextContainerInset()
        }
    }
}
