import Cocoa

class SidebarSplitView: NSSplitView, NSSplitViewDelegate {
    private var isUserDragging = false

    override func draw(_ dirtyRect: NSRect) {
        delegate = self
        super.draw(dirtyRect)
    }
    
    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 && isUserDragging {
            // 当sidebar拖拽到接近最大宽度时，自动展开notelist
            let totalWidth = splitView.frame.width
            let maxSidebarWidth = min(300, totalWidth * 0.3) // sidebar最大宽度约为30%
            
            if proposedPosition >= maxSidebarWidth * 0.9 { // 达到90%时触发
                DispatchQueue.main.async {
                    if let vc = ViewController.shared() {
                        let notelistWidth = vc.splitView.subviews[0].frame.width
                        // 如果notelist已收起，自动展开到合适宽度
                        if notelistWidth == 0 {
                            vc.showNoteList("")
                            // 延迟一下确保展开完成后设置合适宽度
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                let idealNotelistWidth: CGFloat = 280 // 理想的notelist宽度
                                vc.splitView.setPosition(idealNotelistWidth, ofDividerAt: 0)
                            }
                        }
                    }
                }
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
    }
}
