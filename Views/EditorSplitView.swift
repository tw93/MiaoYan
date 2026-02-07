import Cocoa

@MainActor
class EditorSplitView: ThemedSplitView {
    public var shouldHideDivider = false

    override func currentDividerColor() -> NSColor {
        let notelistWidth = subviews.first?.frame.width ?? 0
        let hideDivider = notelistWidth == 0 || shouldHideDivider
        return hideDivider ? Theme.backgroundColor : Theme.dividerColor
    }

    override func minPossiblePositionOfDivider(at dividerIndex: Int) -> CGFloat {
        return 0
    }

    override func maxPossiblePositionOfDivider(at dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 {
            return 600
        }
        return super.maxPossiblePositionOfDivider(at: dividerIndex)
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 {
            if proposedPosition < 180 && proposedPosition > 0 {
                if let vc = AppContext.shared.viewController {
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
        applyDividerColor()
        AppContext.shared.viewController?.viewDidResize()
    }

    func splitViewWillResizeSubviews(_ notification: Notification) {
        if let vc = AppContext.shared.viewController {
            vc.editArea.updateTextContainerInset()
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)

        if let vc = AppContext.shared.viewController {
            // Save notelist width when drag ends
            let notelistWidth = vc.splitView.subviews[0].frame.width
            if notelistWidth > 0 {
                UserDefaultsManagement.sidebarSize = Int(notelistWidth)
            }
        }
    }
}
