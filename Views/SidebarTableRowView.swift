import Cocoa

class SidebarTableRowView: ThemedTableRowView {
    override func selectionRect() -> NSRect {
        let horizontalInset: CGFloat = 6
        let verticalInset: CGFloat = 3
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

    private func indentationOffset() -> CGFloat {
        guard let outlineView = superview as? NSOutlineView else { return 0 }
        let rowIndex = outlineView.row(for: self)
        guard rowIndex >= 0, let item = outlineView.item(atRow: rowIndex) else { return 0 }
        let level = outlineView.level(forItem: item)
        return CGFloat(level) * outlineView.indentationPerLevel
    }
}
