import Cocoa

class MainWindow: NSWindow {
    override func awakeFromNib() {
        super.awakeFromNib()

        guard UserDefaults.standard.object(forKey: "NSWindow Frame myMainWindow") == nil else { return }

        if let screenHeight = NSScreen.main?.frame.height, let screenWidth = NSScreen.main?.frame.width {
            let x = (screenWidth - frame.width) / 2
            let y = (screenHeight - frame.height) / 2
            let rect = NSRect(x: x, y: y, width: frame.width, height: 680)
            self.setFrame(rect, display: true)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount >= 2, isPointInTitleBar(point: event.locationInWindow) {
            performZoom(nil)
        }
        super.mouseUp(with: event)
    }

    fileprivate func isPointInTitleBar(point: CGPoint) -> Bool {
        if let windowFrame = contentView?.frame {
            let titleBarRect = NSRect(x: contentLayoutRect.origin.x, y: contentLayoutRect.origin.y + contentLayoutRect.height, width: contentLayoutRect.width, height: windowFrame.height - contentLayoutRect.height)
            return titleBarRect.contains(point)
        }
        return false
    }
}
