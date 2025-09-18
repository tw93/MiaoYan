import AppKit

extension NSTextStorage: @retroactive @preconcurrency NSTextStorageDelegate {
    @MainActor public func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask != .editedAttributes else { return }
        process(textStorage: textStorage, range: editedRange, changeInLength: delta)
    }

    @MainActor private func process(textStorage: NSTextStorage, range editedRange: NSRange, changeInLength delta: Int) {
        guard let note = EditTextView.note, note.isMarkdown() else { return }
        guard editedRange.length != textStorage.length || EditTextView.shouldForceRescan else { return }

        if shouldScanCompletely(textStorage: textStorage, editedRange: editedRange) {
            rescanAll(textStorage: textStorage)
        } else {
            rescanPartial(textStorage: textStorage, delta: delta, editedRange: editedRange)
        }

        // Call @MainActor loadImages synchronously, no cross-actor dispatch
        loadImages(in: textStorage, checkRange: editedRange)

        EditTextView.shouldForceRescan = false
        EditTextView.lastRemoved = nil
    }

    @MainActor private func shouldScanCompletely(textStorage: NSTextStorage, editedRange: NSRange) -> Bool {
        if editedRange.length == textStorage.length { return true }
        let string = textStorage.mutableString.substring(with: editedRange)
        return string == "`"
            || string == "`\n"
            || EditTextView.lastRemoved == "`"
            || (EditTextView.shouldForceRescan && string.contains("```"))
    }

    @MainActor private func rescanAll(textStorage: NSTextStorage) {
        guard let note = EditTextView.note else { return }
        removeAttribute(.backgroundColor, range: NSRange(0..<textStorage.length))
        NotesTextProcessor.highlightMarkdown(attributedString: textStorage, note: note)
        NotesTextProcessor.highlightFencedAndIndentCodeBlocks(attributedString: textStorage)
    }

    @MainActor private func rescanPartial(textStorage: NSTextStorage, delta: Int, editedRange: NSRange) {
        guard delta == 1 || delta == -1 else {
            highlightMultiline(textStorage: textStorage, editedRange: editedRange)
            return
        }

        let parRange = textStorage.mutableString.paragraphRange(for: editedRange)

        if let fencedRange = NotesTextProcessor.getFencedCodeBlockRange(paragraphRange: parRange, string: textStorage) {
            textStorage.removeAttribute(.backgroundColor, range: parRange)
            highlight(textStorage: textStorage, fencedRange: fencedRange, parRange: parRange, delta: delta, editedRange: editedRange)

            if delta == 1,
               textStorage.mutableString.substring(with: editedRange) == "\n",
               textStorage.length >= fencedRange.upperBound + 1,
               textStorage.attribute(.backgroundColor, at: fencedRange.upperBound, effectiveRange: nil) != nil {
                textStorage.removeAttribute(.backgroundColor, range: NSRange(location: fencedRange.upperBound, length: 1))
            }
        } else {
            highlightParagraph(textStorage: textStorage, editedRange: editedRange)
        }
    }

    @MainActor private func highlight(textStorage: NSTextStorage, fencedRange: NSRange, parRange: NSRange, delta: Int, editedRange: NSRange) {
        let code = textStorage.mutableString.substring(with: fencedRange)
        let language = NotesTextProcessor.getLanguage(code)
        NotesTextProcessor.highlightCode(attributedString: textStorage, range: parRange, language: language)
    }

    @MainActor private func highlight(textStorage: NSTextStorage, indentedRange: [NSRange], intersectedRange: NSRange, editedRange: NSRange) {
        let parRange = textStorage.mutableString.paragraphRange(for: editedRange)
        let checkRange = intersectedRange.length < 500 ? intersectedRange : parRange
        NotesTextProcessor.highlightCode(attributedString: textStorage, range: checkRange)
    }

    @MainActor private func highlightParagraph(textStorage: NSTextStorage, editedRange: NSRange) {
        let codeTextProcessor = CodeTextProcessor(textStorage: textStorage)
        var parRange = textStorage.mutableString.paragraphRange(for: editedRange)
        let paragraph = textStorage.mutableString.substring(with: parRange)

        if paragraph.count == 2,
           textStorage.attributedSubstring(from: parRange).attribute(.backgroundColor, at: 1, effectiveRange: nil) != nil {
            if let ranges = codeTextProcessor.getCodeBlockRanges(parRange: parRange) {
                let invalidateBackgroundRange =
                    ranges.count == 2
                    ? NSRange(ranges.first!.upperBound..<ranges.last!.location)
                    : parRange

                textStorage.removeAttribute(.backgroundColor, range: invalidateBackgroundRange)
                for range in ranges {
                    NotesTextProcessor.highlightCode(attributedString: textStorage, range: range)
                }
            }
        } else {
            textStorage.removeAttribute(.backgroundColor, range: parRange)
        }

        // Proper paragraph scan for two line markup "==" and "--"
        let prevParagraphLocation = parRange.lowerBound - 1
        if prevParagraphLocation > 0, paragraph.starts(with: "==") || paragraph.starts(with: "--") {
            let prev = textStorage.mutableString.paragraphRange(for: NSRange(location: prevParagraphLocation, length: 0))
            parRange = NSRange(location: prev.lowerBound, length: parRange.upperBound - prev.lowerBound)
        }

        guard let note = EditTextView.note else { return }
        NotesTextProcessor.highlightMarkdown(attributedString: textStorage, paragraphRange: parRange, note: note)
        NotesTextProcessor.checkBackTick(styleApplier: textStorage, paragraphRange: parRange)
    }

    @MainActor private func highlightMultiline(textStorage: NSTextStorage, editedRange: NSRange) {
        let parRange = textStorage.mutableString.paragraphRange(for: editedRange)

        if let fencedRange = NotesTextProcessor.getFencedCodeBlockRange(paragraphRange: parRange, string: textStorage) {
            let code = textStorage.mutableString.substring(with: fencedRange)
            let language = NotesTextProcessor.getLanguage(code)
            NotesTextProcessor.highlightCode(attributedString: textStorage, range: parRange, language: language)
        } else {
            guard let note = EditTextView.note else { return }
            NotesTextProcessor.highlightMarkdown(attributedString: textStorage, paragraphRange: parRange, note: note)
            NotesTextProcessor.checkBackTick(styleApplier: textStorage, paragraphRange: parRange)
        }
    }

    // Critical: Mark this function as @MainActor and remove Task dispatching
    @MainActor
    private func loadImages(in textStorage: NSTextStorage, checkRange: NSRange) {
        var start = checkRange.lowerBound
        var finish = checkRange.upperBound

        if checkRange.upperBound < textStorage.length {
            finish = checkRange.upperBound + 1
        }
        if checkRange.lowerBound > 1 {
            start = checkRange.lowerBound - 1
        }

        let affectedRange = NSRange(location: start, length: finish - start)

        textStorage.enumerateAttribute(.attachment, in: affectedRange, options: []) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  textStorage.attribute(.todo, at: range.location, effectiveRange: nil) == nil else { return }

            // Paragraph style: Get and set directly on main thread
            let paragraph = NSTextStorage.getParagraphStyle()
            textStorage.addAttribute(.paragraphStyle, value: paragraph, range: range)

            // Image: Call directly on main thread (assuming loadImage is @MainActor)
            let imageKey = NSAttributedString.Key("com.tw93.miaoyan.image.url")
            if let url = textStorage.attribute(imageKey, at: range.location, effectiveRange: nil) as? URL {
                loadImage(attachment: attachment, url: url, range: range)
            }
        }
    }
}
