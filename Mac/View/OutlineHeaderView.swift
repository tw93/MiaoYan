import Cocoa

class OutlineHeaderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
       super.draw(dirtyRect)

       let lightColor = NSColor(red:1.00, green:1.00, blue:1.00, alpha:1.0)
       let darkColor = NSColor(red:0.09, green:0.11, blue:0.13, alpha:1.0)

       if NSAppearance.current.isDark {
          darkColor.setFill()
       } else {
          lightColor.setFill()
       }

       dirtyRect.fill()
    }
}
