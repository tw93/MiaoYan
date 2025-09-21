import Cocoa
import Foundation

@MainActor
class StorageView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        layer?.backgroundColor = Theme.backgroundColor.cgColor
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated { [self] in
            var f = frame
            f.size.width = 138
            frame = f
            setFrameSize(f.size)
            setBoundsSize(f.size)
        }
    }
}
