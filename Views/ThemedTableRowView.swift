import Cocoa

@MainActor
class ThemedTableRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override var isSelected: Bool {
        didSet {
            if oldValue != isSelected {
                needsDisplay = true
            }
        }
    }

    override var backgroundColor: NSColor {
        get { .clear }
        set {}
    }

    override func drawBackground(in dirtyRect: NSRect) {}

    func selectionRect() -> NSRect {
        return bounds
    }

    override func drawSelection(in dirtyRect: NSRect) {
        if isSelected {
            let path = NSBezierPath(roundedRect: selectionRect(), xRadius: 8, yRadius: 8)
            Theme.selectionBackgroundColor.setFill()
            path.fill()
        }
    }
}
