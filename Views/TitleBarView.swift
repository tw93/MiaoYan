import Cocoa

@MainActor
class TitleBarView: NSView {
    var onMouseEnteredClosure: (() -> Void)?
    var onMouseExitedClosure: (() -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        refreshTrackingAreas()
    }

    override func layout() {
        super.layout()
        refreshTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEnteredClosure?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExitedClosure?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingAreas()
    }

    private func refreshTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }
}
