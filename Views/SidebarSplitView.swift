import Cocoa

@MainActor
class SidebarSplitView: ThemedSplitView {
    private var isUserDragging = false

    override func currentDividerColor() -> NSColor {
        let sidebarWidth = subviews.first?.frame.width ?? 0
        return sidebarWidth == 0 ? Theme.backgroundColor : Theme.dividerColor
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 && isUserDragging {
            if proposedPosition <= 86 {
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
            if sidebarWidth > 86 {
                UserDefaultsManagement.realSidebarSize = Int(sidebarWidth)
            }
        }
    }
}
