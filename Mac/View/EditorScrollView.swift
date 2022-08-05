import Cocoa

class EditorScrollView: NSScrollView {
    private var initialHeight: CGFloat?

    override var isFindBarVisible: Bool {
        set {
            // macOS 10.14 margin hack
            if #available(OSX 10.14, *) {
                if let clip = self.subviews.first as? NSClipView {
                    guard let currentHeight = findBarView?.frame.height else { return }
                    
                    clip.contentInsets.top = newValue ? CGFloat(currentHeight) : 0
                    if newValue, let documentView = self.documentView {
                        documentView.scroll(NSPoint(x: 0, y: CGFloat(-currentHeight)))
                    }
                }
            }

            super.isFindBarVisible = newValue
        }
        get {
            super.isFindBarVisible
        }
    }
}
