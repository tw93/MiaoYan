import Cocoa

@MainActor
class OutlineHeaderView: NSView {
    var onMouseEnteredClosure: (() -> Void)?
    var onMouseExitedClosure: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        Theme.backgroundColor.setFill()
        __NSRectFill(dirtyRect)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated { [self] in
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited], owner: self, userInfo: nil))
        }
    }

    override func layout() {
        super.layout()
        MainActor.assumeIsolated { [self] in
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited], owner: self, userInfo: nil))
        }
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEnteredClosure?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExitedClosure?()
    }
}
