import Cocoa

class SidebarTableRowView: ThemedTableRowView {
    override func selectionBackgroundColor() -> NSColor {
        Theme.sidebarSelectionBackgroundColor
    }

    override func selectionRect() -> NSRect {
        let horizontalInset = Theme.Metrics.selectionInsetH
        let verticalInset = Theme.Metrics.selectionInsetV
        let leadingOffset = indentationOffset()
        let width = max(0, bounds.width - horizontalInset * 2 - leadingOffset)
        return NSRect(
            x: horizontalInset + leadingOffset,
            y: verticalInset,
            width: width,
            height: bounds.height - verticalInset * 2
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        // Don't call super to avoid system drawing
        if isSelected {
            drawSelection(in: dirtyRect)
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }

        let selectionRect = selectionRect()
        let radius = Theme.Metrics.selectionCornerRadius
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: radius, yRadius: radius)
        selectionBackgroundColor().resolvedColor(for: effectiveAppearance).setFill()
        path.fill()

        guard Theme.usesModernSystemChrome else { return }

        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let strokeWidth = 1 / backingScale
        let strokeRect = selectionRect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
        let strokePath = NSBezierPath(roundedRect: strokeRect, xRadius: radius, yRadius: radius)
        strokePath.lineWidth = strokeWidth
        Theme.sidebarSelectionStrokeColor.resolvedColor(for: effectiveAppearance).setStroke()
        strokePath.stroke()
    }

    private func indentationOffset() -> CGFloat {
        guard let outlineView = superview as? NSOutlineView else { return 0 }
        let rowIndex = outlineView.row(for: self)
        guard rowIndex >= 0, let item = outlineView.item(atRow: rowIndex) else { return 0 }
        let level = outlineView.level(forItem: item)
        return CGFloat(level) * outlineView.indentationPerLevel
    }
}
