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

    @MainActor
    public func removeEditorLetterSpacing() {
        let range = NSRange(location: 0, length: length)
        removeAttribute(.kern, range: range)
    }

    // MARK: - Images → Markdown
    @MainActor
    public func unLoadImages(note: Note? = nil) -> NSMutableAttributedString {
        guard let content = mutableCopy() as? NSMutableAttributedString else {
            return NSMutableAttributedString()
        }

        var offset = 0
        let filePathKey = NSAttributedString.Key(rawValue: "\(Bundle.main.bundleIdentifier!).image.path")
        let titleKey = NSAttributedString.Key(rawValue: "\(Bundle.main.bundleIdentifier!).image.title")

        enumerateAttribute(.attachment, in: NSRange(location: 0, length: length)) { value, range, _ in
            guard let textAttachment = value as? NSTextAttachment,
                attribute(.todo, at: range.location, effectiveRange: nil) == nil
            else {
                return
            }

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

    // MARK: - Checkboxes → GFM
    @MainActor
    public func unLoadCheckboxes() -> NSMutableAttributedString {
        guard let content = mutableCopy() as? NSMutableAttributedString else {
            return NSMutableAttributedString()
        }

        var offset = 0
        enumerateAttribute(.attachment, in: NSRange(location: 0, length: length)) { value, range, _ in
            guard value != nil,
                range.length == 1,
                let todoValue = attribute(.todo, at: range.location, effectiveRange: nil) as? Int
            else {
                return
            }

            let newRange = NSRange(location: range.location + offset, length: 1)
            let gfm = todoValue == 1 ? "- [x]" : "- [ ]"
            content.replaceCharacters(in: newRange, with: gfm)
            offset += 4
        }

        return content
    }

    @MainActor
    public func unLoad() -> NSMutableAttributedString {
        unLoadCheckboxes().unLoadImages()
    }

    // MARK: - Underline colors
    @MainActor
    func unLoadUnderlines() -> NSMutableAttributedString {
        enumerateAttribute(.underlineStyle, in: NSRange(location: 0, length: length)) { value, range, _ in
            guard value != nil else { return }
            addAttribute(.underlineColor, value: Theme.underlineColor, range: range)
        }
        return self
    }

    @MainActor
    public func loadUnderlines() {
        enumerateAttribute(.underlineStyle, in: NSRange(location: 0, length: length)) { value, range, _ in
            guard value != nil else { return }
            addAttribute(.underlineColor, value: NotesTextProcessor.underlineColor, range: range)
        }
    }
}
