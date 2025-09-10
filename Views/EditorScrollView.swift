import Cocoa

class EditorScrollView: NSScrollView {
    private var initialHeight: CGFloat?

    override var isFindBarVisible: Bool {
        set {
            if let clip = subviews.first as? NSClipView {
                // 查找find bar的高度
                var currentHeight: CGFloat = 28  // 默认高度

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

            // 只在显示时移除焦点光晕
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.removeFocusRings()
                }
            }
        }
        get {
            super.isFindBarVisible
        }
    }

    // 简化的方法：只移除焦点光晕
    private func removeFocusRings() {
        for subview in subviews {
            removeFocusRingsRecursively(in: subview)
        }
    }

    private func removeFocusRingsRecursively(in view: NSView) {
        // 移除当前视图的焦点光晕
        view.focusRingType = .none
        if let control = view as? NSControl {
            control.focusRingType = .none
            if let cell = control.cell {
                cell.focusRingType = .none
            }
        }

        // 递归处理子视图
        for subview in view.subviews {
            removeFocusRingsRecursively(in: subview)
        }
    }

}
