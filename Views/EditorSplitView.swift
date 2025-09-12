import Cocoa

class EditorSplitView: NSSplitView, NSSplitViewDelegate {
    public var shouldHideDivider = false

    override func awakeFromNib() {
        super.awakeFromNib()
        delegate = self
    }

    override func minPossiblePositionOfDivider(at dividerIndex: Int) -> CGFloat {
        return 0
    }

    override func maxPossiblePositionOfDivider(at dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 {
            return 600  // 最大宽度600px
        }
        return super.maxPossiblePositionOfDivider(at: dividerIndex)
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 {
            // notelist小于180px时自动收起，并联动收起sidebar
            if proposedPosition < 180 && proposedPosition > 0 {
                if let vc = ViewController.shared() {
                    // 使用动画避免闪烁
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.2
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        vc.hideSidebar("")
                    })
                }
                return 0
            }
        }
        return proposedPosition
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        ViewController.shared()?.viewDidResize()
    }

    func splitViewWillResizeSubviews(_ notification: Notification) {
        if let vc = ViewController.shared() {
            vc.editArea.updateTextContainerInset()
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)

        if let vc = ViewController.shared() {
            vc.updateDividers()

            // Save notelist width when drag ends
            let notelistWidth = vc.splitView.subviews[0].frame.width
            if notelistWidth > 0 {
                UserDefaultsManagement.sidebarSize = Int(notelistWidth)
            }
        }
    }
}
