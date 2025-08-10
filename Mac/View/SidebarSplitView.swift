import Cocoa

class SidebarSplitView: NSSplitView, NSSplitViewDelegate {
    private var isUserDragging = false

    override func awakeFromNib() {
        super.awakeFromNib()
        delegate = self
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
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
        // 可以在这里添加其他resize逻辑
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        isUserDragging = false
        
        // Save sidebar width when drag ends
        if let vc = ViewController.shared() {
            let sidebarWidth = vc.sidebarSplitView.subviews[0].frame.width
            if sidebarWidth > 86 {
                UserDefaultsManagement.realSidebarSize = Int(sidebarWidth)
            }
        }
    }
}
