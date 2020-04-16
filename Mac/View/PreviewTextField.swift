import Cocoa

class PreviewTextField: NSTextField {
    override var intrinsicContentSize: NSSize {
        if maximumNumberOfLines == -1 {
            let width = super.intrinsicContentSize.width

            return NSSize(width: width, height: 0)
        }

        return super.intrinsicContentSize
    }
}
