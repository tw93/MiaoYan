import Cocoa

class MainWindow: NSWindow {
    override func awakeFromNib() {
        super.awakeFromNib()

        guard UserDefaults.standard.object(forKey: "NSWindow Frame myMainWindow") == nil else { return }

        if let screenHeight = NSScreen.main?.frame.height, let screenWidth = NSScreen.main?.frame.width {
            let frame = self.frame
            let x = (screenWidth - frame.width) / 2
            let y = (screenHeight - frame.height) / 2
            let rect = NSRect(x: x, y: y, width: frame.width, height: 680)
            self.setFrame(rect, display: true)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount >= 2, self.isPointInTitleBar(point: event.locationInWindow) { // double-click in title bar
            self.performZoom(nil)
        }
        super.mouseUp(with: event)
    }

    fileprivate func isPointInTitleBar(point: CGPoint) -> Bool {
        if let windowFrame = self.contentView?.frame {
            let titleBarRect = NSRect(x: self.contentLayoutRect.origin.x, y: self.contentLayoutRect.origin.y + self.contentLayoutRect.height, width: self.contentLayoutRect.width, height: windowFrame.height - self.contentLayoutRect.height)
            return titleBarRect.contains(point)
        }
        return false
    }
}
