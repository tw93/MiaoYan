import Cocoa
import Foundation

@MainActor
class StorageView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        layer?.backgroundColor = NSColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1.0).cgColor
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        var f = frame
        f.size.width = 138
        frame = f
        setFrameSize(f.size)
        setBoundsSize(f.size)
    }
}
