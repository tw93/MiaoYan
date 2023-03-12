import AppKit
import Cocoa

class NoteRowView: NSTableRowView {
    var isSeparatorHidden = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    override func drawSeparator(in rect: NSRect) {
        if !isSeparatorHidden {
            let bounds = bounds
            NSColor(hex: "#E1E1E1").setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.minX + 22.0, y: bounds.maxY - 0.4))
            path.line(to: NSPoint(x: bounds.maxX - 22.0, y: bounds.maxY - 0.4))
            path.lineWidth = 1.0
            path.stroke()
        }
    }

    override var isEmphasized: Bool {
        set {}
        get {
            false
        }
    }
}
