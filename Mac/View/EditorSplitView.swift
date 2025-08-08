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
            // 如果需要隐藏，允许设置为0，否则最小180px  
            // 如果用户正在拖拽，允许拖拽到更小以触发自动收起
            if shouldHideDivider {
                return 0
            } else if isUserDragging {
                return 0 // 允许拖拽到小于180px以触发自动收起
            } else {
                return 180
            }
        }
        return 0 
    }
    
    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 && isUserDragging && !shouldHideDivider {
            // 如果用户拖拽到小于180px，触发自动收起
            if proposedPosition < 180 {
                DispatchQueue.main.async {
                    if let vc = ViewController.shared() {
                        let sidebarWidth = vc.sidebarSplitView.subviews[0].frame.width
                        // 按照swipe逻辑：先收起sidebar，再收起notelist
                        if sidebarWidth > 0 {
                            vc.hideSidebar("")
                        } else {
                            vc.hideNoteList("")
                        }
                    }
                }
                return 0 // 直接设置为0
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
    }
}
