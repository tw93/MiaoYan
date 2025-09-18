import Cocoa

class EditorScrollView: NSScrollView {
    private var initialHeight: CGFloat?

    override var isFindBarVisible: Bool {
        get {
            super.isFindBarVisible
        }
        set {
            if let clip = subviews.first as? NSClipView {
                var currentHeight: CGFloat = 28

                for subview in subviews {
                    if subview.className.contains("FindBar") || subview.className.contains("NSFindBar") {
                        currentHeight = subview.frame.height
                        break
                    }
                }

                clip.contentInsets.top = newValue ? currentHeight : 0
                if newValue, let documentView = documentView {
                    documentView.scroll(NSPoint(x: 0, y: -currentHeight))
                }
            }

            super.isFindBarVisible = newValue

            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.removeFocusRings()
                }
            }
        }
    }

    private func removeFocusRings() {
        for subview in subviews {
            removeFocusRingsRecursively(in: subview)
        }
    }

    private func removeFocusRingsRecursively(in view: NSView) {
        view.focusRingType = .none
        if let control = view as? NSControl {
            control.focusRingType = .none
            if let cell = control.cell {
                cell.focusRingType = .none
            }
        }

        for subview in view.subviews {
            removeFocusRingsRecursively(in: subview)
        }
    }

}
