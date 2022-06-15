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
}
