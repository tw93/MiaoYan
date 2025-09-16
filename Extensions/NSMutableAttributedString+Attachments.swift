import Foundation

extension NSMutableAttributedString {
    func loadImages(note: Note) {
        let paragraphRange = NSRange(0..<length)
        var offset = 0

        NotesTextProcessor.imageInlineRegex.matches(string, range: paragraphRange) { [weak self] result in
            guard let self = self,
                let originalRange = result?.range
            else { return }

            let adjustedRange = NSRange(location: originalRange.location - offset, length: originalRange.length)
            let mdLink = attributedSubstring(from: adjustedRange).string

            let title = extractTitle(from: result, offset: offset)
            let path = extractPath(from: result, offset: offset)

            guard let cleanPath = path.removingPercentEncoding,
                let imageURL = note.getImageUrl(imageName: cleanPath)
            else { return }

            let cacheUrl = note.project.url.appendingPathComponent("/.cache/")
            let imageAttachment = NoteAttachment(
                title: title,
                path: cleanPath,
                url: imageURL,
                cache: cacheUrl,
                note: note
            )

            guard let attributedStringWithImage = imageAttachment.getAttributedString() else { return }

            offset += mdLink.count - 1
            replaceCharacters(in: adjustedRange, with: attributedStringWithImage)
        }
    }

    private func extractTitle(from result: NSTextCheckingResult?, offset: Int) -> String {
        guard let titleRange = result?.range(at: 2) else { return "" }
        let adjustedRange = NSRange(location: titleRange.location - offset, length: titleRange.length)
        return mutableString.substring(with: adjustedRange)
    }

    private func extractPath(from result: NSTextCheckingResult?, offset: Int) -> String {
        guard let linkRange = result?.range(at: 3) else { return "" }
        let adjustedRange = NSRange(location: linkRange.location - offset, length: linkRange.length)
        return mutableString.substring(with: adjustedRange)
    }
}
