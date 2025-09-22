import Cocoa

@MainActor
class EditorSplitView: NSSplitView, NSSplitViewDelegate {
    public var shouldHideDivider = false

    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated { [self] in
            delegate = self
            applyDividerColor()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyDividerColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyDividerColor()
    }

    override func drawDivider(in rect: NSRect) {
        resolvedDividerColor().setFill()
        NSBezierPath(rect: rect).fill()
    }

    private func currentDividerColor() -> NSColor {
        let notelistWidth = subviews.first?.frame.width ?? 0
        let hideDivider = notelistWidth == 0 || shouldHideDivider
        return hideDivider ? Theme.backgroundColor : Theme.dividerColor
    }

    private func resolvedDividerColor() -> NSColor {
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        return currentDividerColor().resolvedColor(for: appearance)
    }

    private func applyDividerColor() {
        setValue(resolvedDividerColor(), forKey: "dividerColor")
        needsDisplay = true
        displayIfNeeded()
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
            if proposedPosition < 180 && proposedPosition > 0 {
                if let vc = ViewController.shared() {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.2
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        vc.hideSidebar("")
                    })
                }
                return 0
            }
        }
        return proposedPosition
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        applyDividerColor()
        ViewController.shared()?.viewDidResize()
    }

    func splitViewWillResizeSubviews(_ notification: Notification) {
        if let vc = ViewController.shared() {
            vc.editArea.updateTextContainerInset()
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)

        if let vc = ViewController.shared() {
            // Save notelist width when drag ends
            let notelistWidth = vc.splitView.subviews[0].frame.width
            if notelistWidth > 0 {
                UserDefaultsManagement.sidebarSize = Int(notelistWidth)
            }
        }
    }
}
