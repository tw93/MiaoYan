import Cocoa

class NoteRowView: NSTableRowView {

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }
    
    override func drawSelection(in dirtyRect: NSRect) {
        if self.selectionHighlightStyle != .none {
            let selectionRect = NSInsetRect(self.bounds, 6, 0.5)
            
            if NSAppearance.current.isDark {
                NSColor(calibratedWhite: 0, alpha: 1).setStroke()
                NSColor(red: 0.27, green: 0.27, blue: 0.27, alpha: 1).setFill()
            } else {
                NSColor(calibratedWhite: 1, alpha: 1).setStroke()
                NSColor(red: 0.86, green:0.86, blue: 0.86, alpha: 1).setFill()
            }
            
            let selectionPath = NSBezierPath.init(roundedRect: selectionRect, xRadius: 5, yRadius: 5)
            selectionPath.fill()
            selectionPath.stroke()
        }
    }
}
