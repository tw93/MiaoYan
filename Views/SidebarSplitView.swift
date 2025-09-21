import Cocoa

@MainActor
class SidebarSplitView: NSSplitView, NSSplitViewDelegate {
    private var isUserDragging = false

    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated { [self] in
            delegate = self
            if let vc = ViewController.shared() {
                let hidden = (subviews.first?.frame.width ?? 0) == 0
                vc.setDividerColor(for: self, hidden: hidden)
            } else {
                self.setValue(Theme.backgroundColor, forKey: "dividerColor")
            }
        }
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 && isUserDragging {
            // Auto-hide sidebar when too narrow
            if proposedPosition <= 86 {
                DispatchQueue.main.async {
                    if let vc = ViewController.shared() {
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
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        isUserDragging = false

        // Save sidebar width when drag ends
        if let vc = ViewController.shared() {
            let sidebarWidth = vc.sidebarSplitView.subviews[0].frame.width
            // Only save width if sidebar is visible and has reasonable width
            if sidebarWidth > 86 {
                UserDefaultsManagement.realSidebarSize = Int(sidebarWidth)
            } else if sidebarWidth == 0 {
                // If hidden, ensure we preserve the last good width
                // Don't overwrite realSidebarSize when sidebar is hidden
                // This prevents the sidebar from getting smaller each time
            }
        }
    }
}
