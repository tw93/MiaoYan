import Cocoa

@MainActor
class SidebarSplitView: ThemedSplitView {
    private var isUserDragging = false

    override func currentDividerColor() -> NSColor {
        isDividerHidden ? .clear : Theme.splitDividerColor
    }

    private var isDividerHidden: Bool {
        let sidebarWidth = subviews.first?.frame.width ?? 0
        let isSidebarHidden = subviews.first?.isHidden == true
        return isSidebarHidden || sidebarWidth <= Theme.Metrics.collapsedSplitWidthEpsilon
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 && isUserDragging {
            if proposedPosition <= Theme.Metrics.sidebarCollapseSnapWidth {
                DispatchQueue.main.async {
                    if let vc = AppContext.shared.viewController {
                        vc.hideSidebar("")
                    }
                }
                return 0
            }
        }
        return proposedPosition
    }

    func splitViewWillResizeSubviews(_ notification: Notification) {
        isUserDragging = true
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        applyDividerColor()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        isUserDragging = false

        if let vc = AppContext.shared.viewController {
            let sidebarWidth = vc.sidebarSplitView.subviews[0].frame.width
            if sidebarWidth > Theme.Metrics.sidebarCollapseSnapWidth {
                UserDefaultsManagement.realSidebarSize = Int(sidebarWidth)
            }
        }
    }
}
