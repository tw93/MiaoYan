import Cocoa

class EditorSplitView: NSSplitView, NSSplitViewDelegate {
    public var shouldHideDivider = false
    private var isUserDragging = false

    override func draw(_ dirtyRect: NSRect) {
        delegate = self
        super.draw(dirtyRect)
    }

    override func minPossiblePositionOfDivider(at dividerIndex: Int) -> CGFloat { 
        if dividerIndex == 0 {
            // 如果需要隐藏，允许设置为0，否则允许继续拖拽来影响sidebar
            if shouldHideDivider {
                return 0
            } else {
                return 0 // 允许拖拽到0以实现连锁调整效果
            }
        }
        return 0 
    }
    
    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 && isUserDragging && !shouldHideDivider {
            // Auto-hide when reaching 180px threshold
            if proposedPosition <= 180 {
                if let vc = ViewController.shared() {
                    DispatchQueue.main.async {
                        vc.hideNoteList("")
                        vc.hideSidebar("")
                    }
                }
                return 0
            }
            
            if proposedPosition > 600 {
                return 600
            }
        }
        return proposedPosition
    }
    
    override func maxPossiblePositionOfDivider(at dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 {
            return 600 // 最大宽度600px
        }
        return super.maxPossiblePositionOfDivider(at: dividerIndex)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        ViewController.shared()?.viewDidResize()
    }

    func splitViewWillResizeSubviews(_ notification: Notification) {
        isUserDragging = true
        if let vc = ViewController.shared() {
            vc.editArea.updateTextContainerInset()
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        isUserDragging = false
        
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
