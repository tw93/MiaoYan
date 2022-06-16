import Carbon.HIToolbox
import Cocoa
import Highlightr
import MiaoYanCore_macOS

class EditTextView: NSTextView, NSTextFinderClient {
    public static var note: Note?
    public static var isBusyProcessing: Bool = false
    public static var shouldForceRescan: Bool = false
    public static var lastRemoved: String?

    public var viewDelegate: ViewController?

    var isHighlighted: Bool = false
    let storage = Storage.sharedInstance()
    let caretWidth: CGFloat = 1
    var downView: MarkdownView?
    public var timer: Timer?
    public var markdownView: MPreviewView?
    public static var imagesLoaderQueue = OperationQueue()

    public static var fontColor: NSColor {
        if UserDefaultsManagement.appearanceType != AppearanceType.Custom, #available(OSX 10.13, *) {
            return NSColor(named: "mainText")!
        } else {
            return UserDefaultsManagement.fontColor
        }
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var newRect = NSRect(origin: rect.origin, size: rect.size)
        newRect.size.width = caretWidth

        if let range = getParagraphRange(), range.upperBound != textStorage?.length || (
            range.upperBound == textStorage?.length
                && textStorage?.string.last == "\n"
                && selectedRange().location != textStorage?.length
        ) {
            newRect.size.height = newRect.size.height - 3.6
        }

//        let clr = NSColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        super.drawInsertionPoint(in: newRect, color: EditTextView.fontColor, turnedOn: flag)
    }

    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(true)
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        var newInvalidRect = NSRect(origin: invalidRect.origin, size: invalidRect.size)
        newInvalidRect.size.width += caretWidth - 1
        super.setNeedsDisplay(newInvalidRect)
    }

    override func mouseDown(with event: NSEvent) {
        guard EditTextView.note != nil else { return }

        guard let container = textContainer, let manager = layoutManager else { return }

        let point = convert(event.locationInWindow, from: nil)
        let properPoint = NSPoint(x: point.x - textContainerInset.width, y: point.y)

        let index = manager.characterIndex(for: properPoint, in: container, fractionOfDistanceBetweenInsertionPoints: nil)

        let glyphRect = manager.boundingRect(forGlyphRange: NSRange(location: index, length: 1), in: container)

        if glyphRect.contains(properPoint), isTodo(index) {
            guard let f = getTextFormatter() else { return }
            f.toggleTodo(index)

            DispatchQueue.main.async {
                NSCursor.pointingHand.set()
            }
            return
        }

        super.mouseDown(with: event)
        saveCursorPosition()

        if !UserDefaultsManagement.preview {
            isEditable = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let viewController = window?.contentViewController as! ViewController
        if !viewController.emptyEditAreaView.isHidden {
            NSCursor.pointingHand.set()
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let properPoint = NSPoint(x: point.x - textContainerInset.width, y: point.y)

        guard let container = textContainer, let manager = layoutManager else { return }

        let index = manager.characterIndex(for: properPoint, in: container, fractionOfDistanceBetweenInsertionPoints: nil)

        let glyphRect = manager.boundingRect(forGlyphRange: NSRange(location: index, length: 1), in: container)

        if glyphRect.contains(properPoint), isTodo(index) {
            NSCursor.pointingHand.set()
            return
        }

        if UserDefaultsManagement.preview {
            return
        }

        super.mouseMoved(with: event)
    }

    public func isTodo(_ location: Int) -> Bool {
        guard let storage = textStorage else { return false }

        let range = (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        let string = storage.attributedSubstring(from: range).string as NSString

        if storage.attribute(.todo, at: location, effectiveRange: nil) != nil {
            return true
        }

        var length = string.range(of: "- [ ]").length
        if length == 0 {
            length = string.range(of: "- [x]").length
        }

        if length > 0 {
            let upper = range.location + length
            if location >= range.location, location <= upper {
                return true
            }
        }

        return false
    }

    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        let nsString = string as NSString
        let chars = nsString.substring(with: charRange)
        if let notes = storage.getBy(startWith: chars) {
            let titles = notes.map(\.title)
            return titles
        }

        return nil
    }

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [NSPasteboard.PasteboardType.rtfd, NSPasteboard.PasteboardType.string]
    }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let storage = textStorage else { return false }

        let range = selectedRange()
        let attributedString = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))

        if type == .string {
            let plainText = attributedString.unLoadImages().unLoadCheckboxes().string

            pboard.setString(plainText, forType: .string)
            return true
        }
        if type == .rtfd {
            let richString = attributedString.unLoadCheckboxes()
            if let rtfd = try? richString.data(from: NSMakeRange(0, richString.length), documentAttributes: [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtfd]) {
                pboard.setData(rtfd, forType: NSPasteboard.PasteboardType.rtfd)
                return true
            }
        }

        if type.rawValue == "NSStringPboardType" {
            EditTextView.shouldForceRescan = true
            return super.writeSelection(to: pboard, type: type)
        }

        return false
    }

    // 清除最后一行
    override func copy(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)

        if selectedRange.length == 0, let paragraphRange = getParagraphRange(), let paragraph = attributedSubstring(forProposedRange: paragraphRange, actualRange: nil) {
            pasteboard.setString(paragraph.string.trim().removeLastNewLine(), forType: NSPasteboard.PasteboardType.string)
            return
        }
        super.copy(sender)
    }

    override func paste(_ sender: Any?) {
        guard let note = EditTextView.note else { return }

        if pasteImageFromClipboard(in: note) {
            return
        }

        if let clipboard = NSPasteboard.general.string(forType: NSPasteboard.PasteboardType.string) {
            EditTextView.shouldForceRescan = true

            let currentRange = selectedRange()

            breakUndoCoalescing()
            insertText(clipboard, replacementRange: currentRange)
            breakUndoCoalescing()

            saveTextStorageContent(to: note)
            return
        }
        super.paste(sender)
    }

    public func saveImages() {
        guard let storage = textStorage else { return }

        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in

            guard let textAttachment = value as? NSTextAttachment,
                  storage.attribute(.todo, at: range.location, effectiveRange: nil) == nil
            else {
                return
            }

            let filePathKey = NSAttributedString.Key(rawValue: "com.tw93.miaoyan.image.path")

            if (storage.attribute(filePathKey, at: range.location, effectiveRange: nil) as? String) != nil {
                return
            }

            if let note = EditTextView.note,
               let imageData = textAttachment.fileWrapper?.regularFileContents,
               let path = ImagesProcessor.writeFile(data: imageData, note: note)
            {
                storage.addAttribute(filePathKey, value: path, range: range)
            }
        }
    }

    @IBAction func togglePreview(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }

        vc.togglePreview()
    }
    
    @IBAction func togglePresentation(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }

        vc.togglePresentation()
    }

    func getSelectedNote() -> Note? {
        guard let vc = ViewController.shared() else { return nil }

        return vc.notesTableView.getSelectedNote()
    }

    public func isEditable(note: Note) -> Bool {
        if UserDefaultsManagement.preview {
            return false
        }

        return true
    }

    func fill(note: Note, highlight: Bool = false, saveTyping: Bool = false, force: Bool = false) {
        let viewController = window?.contentViewController as! ViewController
        viewController.emptyEditAreaView.isHidden = true
        viewController.titleBarView.isHidden = false

        EditTextView.note = note
        UserDefaultsManagement.lastSelectedURL = note.url

        viewController.updateTitle(newTitle: note.getFileName())

        undoManager?.removeAllActions(withTarget: self)

        if let appd = NSApplication.shared.delegate as? AppDelegate,
           let md = appd.mainWindowController
        {
            md.editorUndoManager = note.undoManager
        }

        isEditable = isEditable(note: note)

        if !saveTyping {
            typingAttributes.removeAll()
            typingAttributes[.font] = UserDefaultsManagement.noteFont
        }

        if UserDefaultsManagement.preview {
            EditTextView.note = nil
            textStorage?.setAttributedString(NSAttributedString())
            EditTextView.note = note

            if markdownView == nil {
                let frame = viewController.editAreaScroll.bounds
                markdownView = MPreviewView(frame: frame, note: note, closure: {})
                if let view = markdownView, EditTextView.note == note {
                    viewController.editAreaScroll.addSubview(view)
                }
            } else {
                /// Resize markdownView
                let frame = viewController.editAreaScroll.bounds
                markdownView?.frame = frame
                /// Load note if needed
                markdownView?.load(note: note, force: force)
            }
            return
        }

        markdownView?.removeFromSuperview()
        markdownView = nil

        guard let storage = textStorage else { return }

        if note.isMarkdown(), let content = note.content.mutableCopy() as? NSMutableAttributedString {
            if UserDefaultsManagement.liveImagesPreview {
                content.loadImages(note: note)
            }
            content.replaceCheckboxes()

            EditTextView.shouldForceRescan = true
            storage.setAttributedString(content)
        } else {
            storage.setAttributedString(note.content)
        }

        if highlight {
            let search = getSearchText()
            let processor = NotesTextProcessor(storage: storage)
            processor.highlightKeyword(search: search)
            isHighlighted = true
        }

        restoreCursorPosition()
        applyLeftParagraphStyle()
    }

    private func setTextColor() {
        if #available(OSX 10.13, *) {
            textColor = NSColor(named: "mainText")
        } else {
            textColor = UserDefaultsManagement.fontColor
        }
    }

    func removeHighlight() {
        guard isHighlighted else {
            return
        }

        isHighlighted = false

        // save cursor position
        let cursorLocation = selectedRanges[0].rangeValue.location

        let search = getSearchText()
        let processor = NotesTextProcessor(storage: textStorage)
        processor.highlightKeyword(search: search, remove: true)

        // restore cursor
        setSelectedRange(NSRange(location: cursorLocation, length: 0))
    }

    public func clear() {
        textStorage?.setAttributedString(NSAttributedString())
        markdownView?.removeFromSuperview()
        markdownView = nil

        isEditable = false

        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        window?.title = appDelegate.appTitle

        if let viewController = window?.contentViewController as? ViewController {
            viewController.emptyEditAreaImage.image = NSImage(imageLiteralResourceName: "makeNoteAsset")
            viewController.emptyEditAreaView.isHidden = false
            viewController.titleBarView.isHidden = true
            viewController.updateTitle(newTitle: "")
        }

        EditTextView.note = nil
    }

    func getParagraphRange() -> NSRange? {
        guard let vc = ViewController.shared(),
              let editArea = vc.editArea,
              let storage = editArea.textStorage
        else {
            return nil
        }

        let range = editArea.selectedRange()
        return storage.mutableString.paragraphRange(for: range)
    }

    func toggleBoldFont(font: NSFont) -> NSFont {
        guard let family = UserDefaultsManagement.noteFont.familyName else {
            return UserDefaultsManagement.noteFont
        }

        var mask = 0
        if font.isBold {
            if font.isItalic {
                mask = NSFontItalicTrait
            }
        } else {
            if font.isItalic {
                mask = NSFontBoldTrait | NSFontItalicTrait
            } else {
                mask = NSFontBoldTrait
            }
        }

        return NSFontManager().font(withFamily: family, traits: NSFontTraitMask(rawValue: NSFontTraitMask.RawValue(mask)), weight: 5, size: CGFloat(UserDefaultsManagement.fontSize))!
    }

    func toggleItalicFont(font: NSFont) -> NSFont? {
        guard let family = UserDefaultsManagement.noteFont.familyName else {
            return UserDefaultsManagement.noteFont
        }

        var mask = 0
        if font.isItalic {
            if font.isBold {
                mask = NSFontBoldTrait
            }
        } else {
            if font.isBold {
                mask = NSFontBoldTrait | NSFontItalicTrait
            } else {
                mask = NSFontItalicTrait
            }
        }

        let size = CGFloat(UserDefaultsManagement.fontSize)
        guard let newFont = NSFontManager().font(withFamily: family, traits: NSFontTraitMask(rawValue: NSFontTraitMask.RawValue(mask)), weight: 5, size: size) else {
            return nil
        }

        return newFont
    }

    override func keyDown(with event: NSEvent) {
        guard !(
            event.modifierFlags.contains(.shift) &&
                [
                    kVK_UpArrow,
                    kVK_DownArrow,
                    kVK_LeftArrow,
                    kVK_RightArrow
                ].contains(Int(event.keyCode))
        ) else {
            super.keyDown(with: event)
            return
        }

        guard let note = EditTextView.note else { return }

        if event.keyCode == kVK_Tab {
            if event.modifierFlags.contains(.shift) {
                let formatter = TextFormatter(textView: self, note: note)
                formatter.unTab()
                saveCursorPosition()
                return
            }
        }

        if event.keyCode == kVK_Return, !hasMarkedText() {
            breakUndoCoalescing()
            let formatter = TextFormatter(textView: self, note: note, shouldScanMarkdown: false)
            formatter.newLine()
            breakUndoCoalescing()
            return
        }

        if event.keyCode == kVK_Delete, event.modifierFlags.contains(.option) {
            deleteWordBackward(nil)
            return
        }

        super.keyDown(with: event)
        saveCursorPosition()
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let note = EditTextView.note else {
            return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        }

        if replacementString == "", let storage = textStorage {
            let lastChar = storage.attributedSubstring(from: affectedCharRange).string
            if lastChar.count == 1 {
                EditTextView.lastRemoved = lastChar
            }
        }

        if note.isMarkdown() {
            deleteUnusedImages(checkRange: affectedCharRange)

            typingAttributes.removeValue(forKey: .todo)

            if let paragraphStyle = typingAttributes[.paragraphStyle] as? NSMutableParagraphStyle {
                paragraphStyle.alignment = .left
            }

            if textStorage?.length == 0 {
                typingAttributes[.foregroundColor] = UserDataService.instance.isDark ? NSColor.white : NSColor.black
            }
        }

        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        var final = flag

        if let event = window?.currentEvent, event.type == .keyDown, ["_", "/"].contains(event.characters) {
            final = false
        }

        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: final)
    }

    func saveCursorPosition() {
        guard let note = EditTextView.note, let range = selectedRanges[0] as? NSRange, UserDefaultsManagement.restoreCursorPosition else {
            return
        }

        viewDelegate?.blockFSUpdates()

        var length = range.lowerBound
        let data = Data(bytes: &length, count: MemoryLayout.size(ofValue: length))
        try? note.url.setExtendedAttribute(data: data, forName: "com.tw93.miaoyan.cursor")
    }

    func restoreCursorPosition() {
        guard let storage = textStorage else { return }

        guard UserDefaultsManagement.restoreCursorPosition else {
            setSelectedRange(NSMakeRange(0, 0))
            return
        }

        var position = storage.length

        if let note = EditTextView.note {
            if let data = try? note.url.extendedAttribute(forName: "com.tw93.miaoyan.cursor") {
                position = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int in
                    ptr.load(as: Int.self)
                }
            }
        }

        if position <= storage.length {
            setSelectedRange(NSMakeRange(position, 0))
        }

        scrollToCursor()
    }

    func saveTextStorageContent(to note: Note) {
        guard note.container != .encryptedTextPack, let storage = textStorage else { return }

        let string = storage.attributedSubstring(from: NSRange(0..<storage.length))

        note.content =
            NSMutableAttributedString(attributedString: string)
                .unLoadImages()
                .unLoadCheckboxes()
    }

    func setEditorTextColor(_ color: NSColor) {
        if let note = EditTextView.note, !note.isMarkdown() {
            textColor = color
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([
            NSPasteboard.PasteboardType(kUTTypeFileURL as String)
        ])

        EditTextView.imagesLoaderQueue.maxConcurrentOperationCount = 3
        EditTextView.imagesLoaderQueue.qualityOfService = .userInteractive
    }

    override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        return NSPoint(x: origin.x, y: origin.y - 7)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        let range = selectedRange
        var data: Data

        guard let note = EditTextView.note, let storage = textStorage else { return false }

        if let data = board.data(forType: .rtfd),
           let text = NSAttributedString(rtfd: data, documentAttributes: nil),
           text.length > 0,
           range.length > 0
        {
            insertText("", replacementRange: range)

            let dropPoint = convert(sender.draggingLocation, from: nil)
            let caretLocation = characterIndexForInsertion(at: dropPoint)

            let mutable = NSMutableAttributedString(attributedString: text)
            mutable.loadCheckboxes()

            insertText(mutable, replacementRange: NSRange(location: caretLocation, length: 0))
            storage.sizeAttachmentImages()

            DispatchQueue.main.async {
                self.setSelectedRange(NSRange(location: caretLocation, length: mutable.length))
            }

            return true
        }

        if let data = board.data(forType: NSPasteboard.PasteboardType(rawValue: "attributedText")), let attributedText = NSKeyedUnarchiver.unarchiveObject(with: data) as? NSMutableAttributedString {
            let dropPoint = convert(sender.draggingLocation, from: nil)
            let caretLocation = characterIndexForInsertion(at: dropPoint)

            let filePathKey = NSAttributedString.Key(rawValue: "com.tw93.miaoyan.image.path")
            let titleKey = NSAttributedString.Key(rawValue: "com.tw93.miaoyan.image.title")
            let positionKey = NSAttributedString.Key(rawValue: "com.tw93.miaoyan.image.position")

            guard
                let path = attributedText.attribute(filePathKey, at: 0, effectiveRange: nil) as? String,
                let title = attributedText.attribute(titleKey, at: 0, effectiveRange: nil) as? String,
                let position = attributedText.attribute(positionKey, at: 0, effectiveRange: nil) as? Int else { return false }

            guard let imageUrl = note.getImageUrl(imageName: path) else { return false }

            let cacheUrl = note.getImageCacheUrl()

            let locationDiff = position > caretLocation ? caretLocation : caretLocation - 1
            let attachment = NoteAttachment(title: title, path: path, url: imageUrl, cache: cacheUrl, invalidateRange: NSRange(location: locationDiff, length: 1))

            guard let attachmentText = attachment.getAttributedString() else { return false }
            guard locationDiff < storage.length else { return false }

            textStorage?.deleteCharacters(in: NSRange(location: position, length: 1))
            textStorage?.replaceCharacters(in: NSRange(location: locationDiff, length: 0), with: attachmentText)

            unLoadImages(note: note)
            setSelectedRange(NSRange(location: caretLocation, length: 0))

            return true
        }

        if let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           urls.count > 0
        {
            let dropPoint = convert(sender.draggingLocation, from: nil)
            let caretLocation = characterIndexForInsertion(at: dropPoint)
            var offset = 0

            unLoadImages(note: note)

            for url in urls {
                do {
                    data = try Data(contentsOf: url)
                } catch {
                    return false
                }

                guard let filePath = ImagesProcessor.writeFile(data: data, url: url, note: note) else { return false }

                let insertRange = NSRange(location: caretLocation + offset, length: 0)
                if UserDefaultsManagement.liveImagesPreview {
                    let cleanPath = filePath.removingPercentEncoding ?? filePath
                    guard let url = note.getImageUrl(imageName: cleanPath) else { return false }

                    let invalidateRange = NSRange(location: caretLocation + offset, length: 1)
                    let attachment = NoteAttachment(title: "", path: cleanPath, url: url, cache: nil, invalidateRange: invalidateRange, note: note)

                    if let string = attachment.getAttributedString() {
                        EditTextView.shouldForceRescan = true

                        insertText(string, replacementRange: insertRange)
                        insertNewline(nil)
                        insertNewline(nil)

                        offset += 3
                    }
                } else {
                    insertText("![](\(filePath))", replacementRange: insertRange)
                    insertNewline(nil)
                    insertNewline(nil)
                }
            }

            if let storage = textStorage {
                NotesTextProcessor.highlightMarkdown(attributedString: storage, note: note)
                saveTextStorageContent(to: note)
                note.save()
                applyLeftParagraphStyle()
            }
            viewDelegate?.notesTableView.reloadRow(note: note)

            return true
        }

        return false
    }

    public func unLoadImages(note: Note) {
        guard note.container != .encryptedTextPack else { return }

        note.save(attributed: attributedString())
    }

    func getSearchText() -> String {
        guard let search = ViewController.shared()?.search else { return String() }

        if let editor = search.currentEditor(), editor.selectedRange.length > 0 {
            return (search.stringValue as NSString).substring(with: NSRange(0..<editor.selectedRange.location))
        }

        return search.stringValue
    }

    public func scrollToCursor() {
        let cursorRange = NSMakeRange(selectedRange().location, 0)
        scrollRangeToVisible(cursorRange)
    }

    public func hasFocus() -> Bool {
        if let fr = window?.firstResponder, fr.isKind(of: EditTextView.self) {
            return true
        }

        return false
    }

    @IBAction func shiftLeft(_ sender: Any) {
        guard let note = EditTextView.note else { return }
        let f = TextFormatter(textView: self, note: note, shouldScanMarkdown: false)

        EditTextView.shouldForceRescan = true
        f.unTab()
    }

    @IBAction func shiftRight(_ sender: Any) {
        guard let note = EditTextView.note else { return }
        let f = TextFormatter(textView: self, note: note, shouldScanMarkdown: false)

        EditTextView.shouldForceRescan = true
        f.tab()
    }

    @IBAction func toggleTodo(_ sender: Any) {
        guard let f = getTextFormatter() else { return }

        f.toggleTodo()
    }

    @IBAction func pressBold(_ sender: Any) {
        guard let vc = ViewController.shared(),
              let editArea = vc.editArea,
              let note = vc.getCurrentNote(),
              !UserDefaultsManagement.preview,
              editArea.isEditable else { return }

        let formatter = TextFormatter(textView: editArea, note: note)
        formatter.bold()
    }

    @IBAction func pressItalic(_ sender: Any) {
        guard let vc = ViewController.shared(),
              let editArea = vc.editArea,
              let note = vc.getCurrentNote(),
              !UserDefaultsManagement.preview,
              editArea.isEditable else { return }

        let formatter = TextFormatter(textView: editArea, note: note)
        formatter.italic()
    }

    @IBAction func insertFileOrImage(_ sender: Any) {
        guard let note = EditTextView.note else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = true
        panel.begin { result in
            if result.rawValue == NSFileHandlingPanelOKButton {
                let urls = panel.urls

                let last = urls.last
                for url in urls {
                    if self.saveFile(url: url, in: note) {
                        if last != url {
                            self.insertNewline(nil)
                            if let vc = ViewController.shared() {
                                vc.notesTableView.reloadRow(note: note)
                            }
                        }
                    }

                    if url != urls.last {
                        self.insertNewline(nil)
                    }
                }
            }
        }
    }

    @IBAction func insertCodeBlock(_ sender: NSButton) {
        let currentRange = selectedRange()

        if currentRange.length > 0 {
            let mutable = NSMutableAttributedString(string: "```\n")
            if let substring = attributedSubstring(forProposedRange: currentRange, actualRange: nil) {
                mutable.append(substring)

                if substring.string.last != "\n" {
                    mutable.append(NSAttributedString(string: "\n"))
                }
            }

            mutable.append(NSAttributedString(string: "```\n"))

            EditTextView.shouldForceRescan = true
            insertText(mutable, replacementRange: currentRange)
            setSelectedRange(NSRange(location: currentRange.location + 3, length: 0))

            return
        }

        if textStorage?.length == 0 {
            EditTextView.shouldForceRescan = true
        }

        insertText("```\n\n```\n", replacementRange: currentRange)
        setSelectedRange(NSRange(location: currentRange.location + 3, length: 0))
    }

    @IBAction func insertCodeSpan(_ sender: NSMenuItem) {
        let currentRange = selectedRange()

        if currentRange.length > 0 {
            let mutable = NSMutableAttributedString(string: "`")
            if let substring = attributedSubstring(forProposedRange: currentRange, actualRange: nil) {
                mutable.append(substring)
            }

            mutable.append(NSAttributedString(string: "`"))

            EditTextView.shouldForceRescan = true
            insertText(mutable, replacementRange: currentRange)
            return
        }

        insertText("``", replacementRange: currentRange)
        setSelectedRange(NSRange(location: currentRange.location + 1, length: 0))
    }

    @IBAction func insertLink(_ sender: Any) {
        guard let vc = ViewController.shared(),
              let editArea = vc.editArea,
              let note = vc.getCurrentNote(),
              !UserDefaultsManagement.preview,
              editArea.isEditable else { return }

        let formatter = TextFormatter(textView: editArea, note: note)
        formatter.link()
    }

    private func getTextFormatter() -> TextFormatter? {
        guard let note = EditTextView.note else { return nil }

        return TextFormatter(textView: self, note: note)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let selected = attributedSubstring(forProposedRange: selectedRange(), actualRange: nil) else { return .generic }

        let attributedString = NSMutableAttributedString(attributedString: selected)
        let positionKey = NSAttributedString.Key(rawValue: "com.tw93.miaoyan.image.position")
        attributedString.addAttribute(positionKey, value: selectedRange().location, range: NSRange(0..<1))

        let data = NSKeyedArchiver.archivedData(withRootObject: attributedString)
        let type = NSPasteboard.PasteboardType(rawValue: "attributedText")
        let board = sender.draggingPasteboard
        board.setData(data, forType: type)

        return .copy
    }

    override func clicked(onLink link: Any, at charIndex: Int) {
        if let link = link as? String, link.isValidEmail(), let mail = URL(string: "mailto:\(link)") {
            NSWorkspace.shared.open(mail)
            return
        }

        let range = NSRange(location: charIndex, length: 1)

        let char = attributedSubstring(forProposedRange: range, actualRange: nil)
        if char?.attribute(.attachment, at: 0, effectiveRange: nil) == nil {
            if NSEvent.modifierFlags.contains(.command), let link = link as? String, let url = URL(string: link) {
                _ = try? NSWorkspace.shared.open(url, options: .withoutActivation, configuration: [:])
                return
            }

            super.clicked(onLink: link, at: charIndex)
            return
        }

        if !UserDefaultsManagement.liveImagesPreview {
            let url = URL(fileURLWithPath: link as! String)
            NSWorkspace.shared.open(url)
            return
        }

        let pathKey = NSAttributedString.Key(rawValue: "com.tw93.miaoyan.image.path")
        let titleKey = NSAttributedString.Key(rawValue: "com.tw93.miaoyan.image.title")

        if let event = NSApp.currentEvent,
           !event.modifierFlags.contains(.command),
           let note = EditTextView.note,
           let path = (char?.attribute(pathKey, at: 0, effectiveRange: nil) as? String)?.removingPercentEncoding,
           let url = note.getImageUrl(imageName: path)
        {
            if !url.isImage {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return
            }

            let isOpened = NSWorkspace.shared.openFile(url.path, withApplication: "Preview", andDeactivate: true)

            if isOpened { return }

            let url = URL(fileURLWithPath: url.path)
            NSWorkspace.shared.open(url)
            return
        }

        guard let window = MainWindowController.shared() else { return }
        guard let vc = window.contentViewController as? ViewController else { return }

        vc.alert = NSAlert()
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 290, height: 20))
        field.placeholderString = "All Hail the Crimson King"

        if let title = char?.attribute(titleKey, at: 0, effectiveRange: nil) as? String {
            field.stringValue = title
        }

        vc.alert?.messageText = NSLocalizedString("Please enter image title:", comment: "Edit area")
        vc.alert?.accessoryView = field
        vc.alert?.alertStyle = .informational
        vc.alert?.addButton(withTitle: "OK")
        vc.alert?.beginSheetModal(for: window) { (returnCode: NSApplication.ModalResponse) in
            if returnCode == NSApplication.ModalResponse.alertFirstButtonReturn {
                self.textStorage?.addAttribute(titleKey, value: field.stringValue, range: range)

                if let note = vc.notesTableView.getSelectedNote(), note.container != .encryptedTextPack {
                    note.save(attributed: self.attributedString())
                }
            }

            vc.alert = nil
        }

        field.becomeFirstResponder()
    }

    public func applyLeftParagraphStyle() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(UserDefaultsManagement.editorLineSpacing)
        paragraphStyle.alignment = .left
        typingAttributes[.paragraphStyle] = paragraphStyle
        defaultParagraphStyle = paragraphStyle
        textStorage?.updateParagraphStyle()
    }

    override func viewDidChangeEffectiveAppearance() {
        guard let note = EditTextView.note else { return }

        UserDataService.instance.isDark = effectiveAppearance.isDark
        UserDefaultsManagement.codeTheme = effectiveAppearance.isDark ? "atom-one-dark" : "vs"

        NotesTextProcessor.hl = nil
        NotesTextProcessor.highlight(note: note)

        let funcName = effectiveAppearance.isDark ? "switchToDarkMode" : "switchToLightMode"
        let switchScript = "if (typeof(\(funcName)) == 'function') { \(funcName)(); }"

        downView?.evaluateJavaScript(switchScript)
        viewDelegate?.refillEditArea()
    }

    private func pasteImageFromClipboard(in note: Note) -> Bool {
        if let url = NSURL(from: NSPasteboard.general) {
            if !url.isFileURL {
                return false
            }

            return saveFile(url: url as URL, in: note)
        }

        if let clipboard = NSPasteboard.general.data(forType: .tiff), let image = NSImage(data: clipboard), let jpgData = image.jpgData {
            EditTextView.shouldForceRescan = true

            saveClipboard(data: jpgData, note: note)
            saveTextStorageContent(to: note)
            note.save()

            textStorage?.sizeAttachmentImages()
            return true
        }

        return false
    }

    private func saveFile(url: URL, in note: Note) -> Bool {
        if let data = try? Data(contentsOf: url) {
            var ext: String?

            if let _ = NSImage(data: data) {
                ext = "jpg"
                if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                    let uti = CGImageSourceGetType(source)

                    if let fileExtension = (uti as String?)?.utiFileExtension {
                        ext = fileExtension
                    }
                }
            }

            EditTextView.shouldForceRescan = true

            saveClipboard(data: data, note: note, ext: ext, url: url)
            saveTextStorageContent(to: note)
            note.save()

            textStorage?.sizeAttachmentImages()

            return true
        }

        return false
    }

    private func saveClipboard(data: Data, note: Note, ext: String? = nil, url: URL? = nil) {
        if let path = ImagesProcessor.writeFile(data: data, url: url, note: note, ext: ext) {
            guard UserDefaultsManagement.liveImagesPreview else {
                let newLineImage = NSAttributedString(string: "![](\(path))")
                breakUndoCoalescing()
                insertText(newLineImage, replacementRange: selectedRange())
                breakUndoCoalescing()
                return
            }

            guard let path = path.removingPercentEncoding else { return }

            if let imageUrl = note.getImageUrl(imageName: path) {
                let range = NSRange(location: selectedRange.location, length: 1)
                let attachment = NoteAttachment(title: "", path: path, url: imageUrl, cache: nil, invalidateRange: range, note: note)

                if let attributedString = attachment.getAttributedString() {
                    let newLineImage = NSMutableAttributedString(attributedString: attributedString)

                    breakUndoCoalescing()
                    insertText(newLineImage, replacementRange: selectedRange())
                    breakUndoCoalescing()
                    return
                }
            }
        }
    }

    public func updateTextContainerInset() {
        let lineWidth = UserDefaultsManagement.lineWidth
        let margin = UserDefaultsManagement.marginSize
        let width = frame.width

        if lineWidth == 1000 {
            textContainerInset.width = CGFloat(margin)
            return
        }

        guard Float(width) - Float(margin * 2) > Float(lineWidth) else {
            textContainerInset.width = CGFloat(margin)
            return
        }

        let inset = (Int(Float(width)) - lineWidth) / 2

        textContainerInset.width = CGFloat(inset)
    }

    private func deleteUnusedImages(checkRange: NSRange) {
        guard let storage = textStorage else { return }
        guard let note = EditTextView.note else { return }

        var removedImages = [URL: URL]()

        storage.enumerateAttribute(.attachment, in: checkRange) { value, range, _ in
            if let _ = value as? NSTextAttachment, storage.attribute(.todo, at: range.location, effectiveRange: nil) == nil {
                let filePathKey = NSAttributedString.Key(rawValue: "com.tw93.miaoyan.image.path")

                if let filePath = storage.attribute(filePathKey, at: range.location, effectiveRange: nil) as? String {
                    if let note = EditTextView.note {
                        guard let imageURL = note.getImageUrl(imageName: filePath) else { return }

                        do {
                            guard let resultingItemUrl = Storage.sharedInstance().trashItem(url: imageURL) else { return }

                            try FileManager.default.moveItem(at: imageURL, to: resultingItemUrl)

                            removedImages[resultingItemUrl] = imageURL
                        } catch {
                            print(error)
                        }
                    }
                }
            }
        }

        if removedImages.count > 0 {
            note.undoManager.registerUndo(withTarget: self, selector: #selector(unDeleteImages), object: removedImages)
        }
    }

    @objc public func unDeleteImages(_ urls: [URL: URL]) {
        for (src, dst) in urls {
            do {
                try FileManager.default.moveItem(at: src, to: dst)
            } catch {
                print(error)
            }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)

        let editTitle = NSLocalizedString("Edit Link…", comment: "")
        if let editLink = menu?.item(withTitle: editTitle) {
            menu?.removeItem(editLink)
        }

        let removeTitle = NSLocalizedString("Remove Link", comment: "")
        if let removeLink = menu?.item(withTitle: removeTitle) {
            menu?.removeItem(removeLink)
        }

        return menu
    }
}
