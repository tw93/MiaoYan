import AppKit
import Foundation

extension NSTextStorage {

    // Read UserDefaultsManagement, modify font attributes → UI related, main thread execution
    @MainActor
    public func updateFont() {
        beginEditing()
        enumerateAttribute(.font, in: NSRange(location: 0, length: length)) { value, range, _ in
            if let font = value as? NSFont, let familyName = UserDefaultsManagement.noteFont.familyName {
                let newFontDescriptor = font.fontDescriptor
                    .withFamily(familyName)
                    .withSymbolicTraits(font.fontDescriptor.symbolicTraits)

                if let newFont = NSFont(descriptor: newFontDescriptor, size: CGFloat(UserDefaultsManagement.fontSize)) {
                    removeAttribute(.font, range: range)
                    addAttribute(.font, value: newFont, range: range)
                    fixAttributes(in: range)
                }
            }
        }
        endEditing()
    }

    // Read line height/spacing config, return paragraph style → UI state, main thread safe
    @MainActor
    public static func getParagraphStyle() -> NSMutableParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        let fontSize = UserDefaultsManagement.fontSize

        let editorLineHeight = UserDefaultsManagement.editorLineHeight
        let editorLineSpacing = UserDefaultsManagement.editorLineSpacing
        let lineHeight = CGFloat(editorLineHeight * CGFloat(fontSize)) + editorLineSpacing

        paragraphStyle.alignment = .left
        paragraphStyle.lineSpacing = editorLineSpacing
        paragraphStyle.lineHeightMultiple = editorLineHeight
        paragraphStyle.maximumLineHeight = lineHeight
        paragraphStyle.minimumLineHeight = lineHeight

        return paragraphStyle
    }

    // Batch apply paragraph style → modify attributed text properties, main thread
    @MainActor
    public func updateParagraphStyle() {
        beginEditing()
        let attachmentParagraph = NSTextStorage.getParagraphStyle()
        mutableString.enumerateSubstrings(in: NSRange(location: 0, length: length), options: .byParagraphs) { _, range, _, _ in
            let rangeNewline = range.upperBound == self.length ? range : NSRange(location: range.location, length: range.length + 1)
            self.addAttribute(.paragraphStyle, value: attachmentParagraph, range: rangeNewline)
        }
        endEditing()
    }

    // Iterate attachments to scale images per config, replace attachment cells → involves AppKit images and cells, main thread
    @MainActor
    public func sizeAttachmentImages() {
        enumerateAttribute(.attachment, in: NSRange(location: 0, length: length)) { value, range, _ in
            if let attachment = value as? NSTextAttachment,
               attribute(.todo, at: range.location, effectiveRange: nil) == nil {

                if let imageData = attachment.fileWrapper?.regularFileContents,
                   var image = NSImage(data: imageData),
                   let rep = image.representations.first {

                    var maxWidth = UserDefaultsManagement.imagesWidth
                    if maxWidth == Float(1000) {
                        maxWidth = Float(rep.pixelsWide)
                    }

                    let ratio = Float(maxWidth) / Float(rep.pixelsWide)
                    var size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
                    if ratio < 1 {
                        size = NSSize(width: Int(maxWidth), height: Int(Float(rep.pixelsHigh) * ratio))
                    }

                    if let resized = image.resize(to: size) {
                        image = resized
                    }

                    // These APIs are MainActor isolated in Swift 6
                    let cell = NSTextAttachmentCell(imageCell: NSImage(size: size))
                    cell.image = image
                    attachment.attachmentCell = cell

                    addAttribute(.link, value: String(), range: range)
                }
            }
        }
    }
}
