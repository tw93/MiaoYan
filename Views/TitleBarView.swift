import Cocoa

@MainActor
class TitleBarView: NSView {
    var onMouseEnteredClosure: (() -> Void)?
    var onMouseExitedClosure: (() -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited], owner: self, userInfo: nil))
    }

    override func layout() {
        super.layout()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEnteredClosure?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExitedClosure?()
    }
}
