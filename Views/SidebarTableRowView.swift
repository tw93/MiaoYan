import Cocoa

class SidebarTableRowView: ThemedTableRowView {
    override func selectionRect() -> NSRect {
        let margin: CGFloat = 12
        return NSRect(
            x: margin,
            y: 3,
            width: max(0, bounds.width - 2 * margin),
            height: bounds.height - 6
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        // Don't call super to avoid system drawing
        if isSelected {
            drawSelection(in: dirtyRect)
        }
    }
}
