import Cocoa
import Foundation

extension NSMutableAttributedString {
    // MARK: - Letter Spacing Support
    @MainActor
    public func applyEditorLetterSpacing(_ spacing: CGFloat? = nil) {
        let letterSpacing = spacing ?? UserDefaultsManagement.editorLetterSpacing
        guard letterSpacing != 0 else { return }
        let range = NSRange(location: 0, length: length)
        addAttribute(.kern, value: letterSpacing as Any, range: range)
    }

    @MainActor
    public func applyEditorLetterSpacing(in range: NSRange, spacing: CGFloat? = nil) {
        let letterSpacing = spacing ?? UserDefaultsManagement.editorLetterSpacing
        guard letterSpacing != 0,
            range.location < length,
            range.upperBound <= length
        else { return }
        addAttribute(.kern, value: letterSpacing as Any, range: range)
    }

    // MARK: - Images → Markdown
    @MainActor
    public func unLoadImages(note: Note? = nil) -> NSMutableAttributedString {
        guard let content = mutableCopy() as? NSMutableAttributedString else {
            return NSMutableAttributedString()
        }

        var offset = 0
        let filePathKey = NSAttributedString.Key(rawValue: AppIdentifier.imagePathKey)
        let titleKey = NSAttributedString.Key(rawValue: AppIdentifier.imageTitleKey)

        enumerateAttribute(.attachment, in: NSRange(location: 0, length: length)) { value, range, _ in
            guard let textAttachment = value as? NSTextAttachment else { return }

            let path = self.extractImagePath(textAttachment: textAttachment, note: note, filePathKey: filePathKey)
            let title = attribute(titleKey, at: range.location, effectiveRange: nil) as? String ?? ""

            guard let imagePath = path, !imagePath.isEmpty else { return }

            let newRange = NSRange(location: range.location + offset, length: range.length)
            content.removeAttribute(.attachment, range: newRange)
            content.replaceCharacters(in: newRange, with: "![\(title)](\(imagePath))")
            offset += 4 + imagePath.count + title.count
        }

        return content
    }

    @MainActor
    private func extractImagePath(textAttachment: NSTextAttachment, note: Note?, filePathKey: NSAttributedString.Key) -> String? {
        if let filePath = attribute(filePathKey, at: 0, effectiveRange: nil) as? String {
            return filePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        }

        guard let note = note else { return nil }

        if let imageData = textAttachment.fileWrapper?.regularFileContents {
            return ImagesProcessor.writeFile(data: imageData, note: note)
        }

        if let imageData = textAttachment.contents {
            return ImagesProcessor.writeFile(data: imageData, note: note)
        }

        return nil
    }

    @MainActor
    public func unLoad() -> NSMutableAttributedString {
        unLoadImages()
    }

    // MARK: - Underline colors

}

extension NSAttributedString {
    /// Whether any character carries an attachment, the only thing the
    /// image and checkbox unload passes act on. `containsAttachments` gives
    /// the same answer several times slower on a long, styled buffer, and
    /// the save path asks on every keystroke.
    var hasAttachmentAttribute: Bool {
        var found = false
        enumerateAttribute(.attachment, in: NSRange(location: 0, length: length)) { value, _, stop in
            guard value != nil else { return }
            found = true
            stop.pointee = true
        }
        return found
    }
}
