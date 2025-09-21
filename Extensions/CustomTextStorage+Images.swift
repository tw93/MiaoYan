import AVKit
import Cocoa

extension NSTextStorage {
    private struct AttachmentBox: @unchecked Sendable {
        weak var attachment: NSTextAttachment?
    }

    @MainActor public func loadImage(attachment: NSTextAttachment, url: URL, range: NSRange) {
        guard url.isImage else { return }

        let size = attachment.bounds.size
        let retinaSize = CGSize(width: size.width * 2, height: size.height * 2)
        let box = AttachmentBox(attachment: attachment)

        EditTextView.imagesLoaderQueue.addOperation {
            let image = NoteAttachment.getImage(url: url, size: retinaSize)

            Task { @MainActor in
                guard let attachment = box.attachment else { return }

                let cell = NSTextAttachmentCell(imageCell: image)
                cell.image?.size = size
                attachment.image = nil
                attachment.attachmentCell = cell
                attachment.bounds = NSRect(x: 0, y: 0, width: size.width, height: size.height)

                if let manager = ViewController.shared()?.editArea.layoutManager {
                    manager.invalidateDisplay(forCharacterRange: range)
                }
            }
        }
    }
}
