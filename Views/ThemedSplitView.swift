import Cocoa

@MainActor
class ThemedSplitView: NSSplitView, NSSplitViewDelegate {
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

    func currentDividerColor() -> NSColor {
        return Theme.dividerColor
    }

    func resolvedDividerColor() -> NSColor {
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        return currentDividerColor().resolvedColor(for: appearance)
    }

    func applyDividerColor() {
        setValue(resolvedDividerColor(), forKey: "dividerColor")
        needsDisplay = true
        displayIfNeeded()
    }
}
