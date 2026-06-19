import Cocoa

@MainActor
class EditorSplitView: ThemedSplitView {
    public var shouldHideDivider = false

    override func currentDividerColor() -> NSColor {
        isDividerHidden ? .clear : Theme.splitDividerColor
    }

    private var isDividerHidden: Bool {
        let notelistWidth = subviews.first?.frame.width ?? 0
        let isNotelistHidden = subviews.first?.isHidden == true
        return isNotelistHidden || notelistWidth <= Theme.Metrics.collapsedSplitWidthEpsilon || shouldHideDivider
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
            if proposedPosition < Theme.Metrics.noteListCollapseSnapWidth && proposedPosition > 0 {
                if let vc = AppContext.shared.viewController {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.2
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        vc.hideNoteList("")
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
            if notelistWidth >= Theme.Metrics.noteListMinimumWidth {
                UserDefaultsManagement.sidebarSize = Int(notelistWidth)
            }
        }
    }
}
