import Cocoa

class SidebarTableRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get {
            false
        }
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
        get {
            return .clear
        }
        set {
            // Ignore attempts to set background color
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        if isSelected {
            // Create subtle rounded selection like modern macOS sidebar
            let margin: CGFloat = 12
            let cornerRadius: CGFloat = 8
            let selectionRect = NSRect(
                x: margin,
                y: 3,
                width: max(0, bounds.width - 2 * margin),
                height: bounds.height - 6
            )

            let path = NSBezierPath(roundedRect: selectionRect, xRadius: cornerRadius, yRadius: cornerRadius)

            // Use system-appropriate colors that work across all macOS versions
            if NSApp.effectiveAppearance.isDark {
                // Dark mode: subtle highlight with proper contrast
                NSColor(calibratedWhite: 0.25, alpha: 1.0).setFill()
            } else {
                // Light mode: system-like selection with proper contrast
                NSColor(calibratedWhite: 0.85, alpha: 1.0).setFill()
            }

            path.fill()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Don't call super to avoid any system drawing

        // Draw our custom selection if selected
        if isSelected {
            drawSelection(in: dirtyRect)
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        // Override to prevent any background drawing
    }
}
