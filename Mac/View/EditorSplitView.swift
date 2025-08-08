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
            // 实现经典macOS 3栏连锁调整效果
            if proposedPosition < 180 {
                // 当notelist宽度小于180px时，开始影响sidebar宽度
                if let vc = ViewController.shared() {
                    let sidebarWidth = vc.sidebarSplitView.subviews[0].frame.width
                    let totalAvailable = sidebarWidth + proposedPosition
                    
                    // 计算新的sidebar宽度，确保总宽度保持合理
                    let newSidebarWidth = max(0, totalAvailable - 180)
                    let newNotelistWidth = totalAvailable - newSidebarWidth
                    
                    // 异步调整sidebar宽度以实现连锁效果
                    DispatchQueue.main.async {
                        vc.sidebarSplitView.setPosition(newSidebarWidth, ofDividerAt: 0)
                    }
                    
                    return newNotelistWidth
                }
            }
            
            // 正常范围内的约束
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
        
        // 拖拽结束后，确保边框线状态正确
        if let vc = ViewController.shared() {
            vc.updateDividers()
        }
    }
}
