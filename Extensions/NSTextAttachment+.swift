import Cocoa

extension NSTextAttachment {
    func isFile() -> Bool {
        return (attachmentCell?.cellSize().height == 40)
    }
}
