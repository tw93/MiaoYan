import Cocoa

@MainActor
class SidebarSplitView: NSSplitView, NSSplitViewDelegate {
    private var isUserDragging = false

    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated { [self] in
            delegate = self
            setValue(NSColor(named: "divider"), forKey: "dividerColor")
        }
    }

    func updateDividerVisibility() {
        let sidebarWidth = subviews.first?.frame.width ?? 0
        let dividerColor = sidebarWidth == 0 ? Theme.backgroundColor : NSColor(named: "divider")
        setValue(dividerColor, forKey: "dividerColor")
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 && isUserDragging {
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
        updateDividerVisibility()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        isUserDragging = false

        if let vc = ViewController.shared() {
            let sidebarWidth = vc.sidebarSplitView.subviews[0].frame.width
            if sidebarWidth > 86 {
                UserDefaultsManagement.realSidebarSize = Int(sidebarWidth)
            }
        }
    }
}
