import Cocoa

class DragOperationHandler {
    private weak var textView: EditTextView?

    init(textView: EditTextView) {
        self.textView = textView
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let textView = textView,
            let note = EditTextView.note,
            let storage = textView.textStorage
        else { return false }

        let board = sender.draggingPasteboard
        let selectedRange = textView.selectedRange

        // 处理富文本拖拽
        if let rtfdData = board.data(forType: .rtfd) {
            return handleRTFDrop(rtfdData: rtfdData, selectedRange: selectedRange, sender: sender, storage: storage)
        }

        // 处理属性文本拖拽（图片）
        if let attributedData = board.data(forType: NSPasteboard.PasteboardType(rawValue: "attributedText")) {
            return handleAttributedTextDrop(data: attributedData, sender: sender, note: note, storage: storage)
        }

        // 处理文件URL拖拽
        if let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
            !urls.isEmpty
        {
            return handleFileURLsDrop(urls: urls, sender: sender, note: note, storage: storage)
        }

        return false
    }

    private func handleRTFDrop(rtfdData: Data, selectedRange: NSRange, sender: NSDraggingInfo, storage: NSTextStorage) -> Bool {
        guard let textView = textView,
            let text = NSAttributedString(rtfd: rtfdData, documentAttributes: nil),
            text.length > 0,
            selectedRange.length > 0
        else { return false }

        textView.insertText("", replacementRange: selectedRange)

        let dropPoint = textView.convert(sender.draggingLocation, from: nil)
        let caretLocation = textView.characterIndexForInsertion(at: dropPoint)

        let mutable = NSMutableAttributedString(attributedString: text)
        textView.insertText(mutable, replacementRange: NSRange(location: caretLocation, length: 0))
        storage.sizeAttachmentImages()

        DispatchQueue.main.async {
            textView.setSelectedRange(NSRange(location: caretLocation, length: mutable.length))
        }

        return true
    }

    private func handleAttributedTextDrop(data: Data, sender: NSDraggingInfo, note: Note, storage: NSTextStorage) -> Bool {
        guard let textView = textView,
            let attributedText = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSMutableAttributedString.self, from: data)
        else { return false }

        let dropPoint = textView.convert(sender.draggingLocation, from: nil)
        let caretLocation = textView.characterIndexForInsertion(at: dropPoint)

        let filePathKey = NSAttributedString.Key(rawValue: "com.tw93.miaoyan.image.path")
        let titleKey = NSAttributedString.Key(rawValue: "com.tw93.miaoyan.image.title")
        let positionKey = NSAttributedString.Key(rawValue: "com.tw93.miaoyan.image.position")

        guard
            let path = attributedText.attribute(filePathKey, at: 0, effectiveRange: nil) as? String,
            let title = attributedText.attribute(titleKey, at: 0, effectiveRange: nil) as? String,
            let position = attributedText.attribute(positionKey, at: 0, effectiveRange: nil) as? Int,
            let imageUrl = note.getImageUrl(imageName: path)
        else { return false }

        let cacheUrl = note.getImageCacheUrl()
        let locationDiff = position > caretLocation ? caretLocation : caretLocation - 1

        guard locationDiff >= 0 && locationDiff < storage.length else { return false }

        let attachment = NoteAttachment(title: title, path: path, url: imageUrl, cache: cacheUrl, invalidateRange: NSRange(location: locationDiff, length: 1))

        guard let attachmentText = attachment.getAttributedString() else { return false }

        textView.textStorage?.deleteCharacters(in: NSRange(location: position, length: 1))
        textView.textStorage?.replaceCharacters(in: NSRange(location: locationDiff, length: 0), with: attachmentText)

        textView.unLoadImages(note: note)
        textView.setSelectedRange(NSRange(location: caretLocation, length: 0))

        return true
    }

    private func handleFileURLsDrop(urls: [URL], sender: NSDraggingInfo, note: Note, storage: NSTextStorage) -> Bool {
        guard let textView = textView else { return false }

        let dropPoint = textView.convert(sender.draggingLocation, from: nil)
        let caretLocation = textView.characterIndexForInsertion(at: dropPoint)

        textView.unLoadImages(note: note)

        var insertionOffset = 0

        for url in urls {
            do {
                let data = try Data(contentsOf: url)
                guard let filePath = ImagesProcessor.writeFile(data: data, url: url, note: note) else { continue }

                let insertRange = NSRange(location: caretLocation + insertionOffset, length: 0)
                textView.insertText("![](\(filePath))", replacementRange: insertRange)
                textView.insertNewline(nil)
                textView.insertNewline(nil)

                insertionOffset += filePath.count + 6  // "![]()" + 2 newlines
            } catch {
                continue  // 跳过无法读取的文件
            }
        }

        NotesTextProcessor.highlightMarkdown(attributedString: storage, note: note)
        textView.saveTextStorageContent(to: note)
        note.save()
        textView.viewDelegate?.notesTableView.reloadRow(note: note)

        return true
    }
}
