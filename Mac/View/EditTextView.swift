import Alamofire
import Carbon.HIToolbox
import Cocoa
import Highlightr
import SwiftyJSON

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
    var initRange = NSRange(location: 0, length: 0)

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

    override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        return NSPoint(x: origin.x, y: origin.y - 7)
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([
            NSPasteboard.PasteboardType(kUTTypeFileURL as String)
        ])

        EditTextView.imagesLoaderQueue.maxConcurrentOperationCount = 3
        EditTextView.imagesLoaderQueue.qualityOfService = .userInteractive
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var newRect = NSRect(origin: rect.origin, size: rect.size)
        newRect.size.width = caretWidth
        var diff = 4.0
        if let range = getParagraphRange(), range.upperBound != textStorage?.length || (
            range.upperBound == textStorage?.length
                && textStorage?.string.last == "\n"
                && selectedRange().location != textStorage?.length
        ) {
            diff = 6.0
        }

        newRect.size.height = newRect.size.height - diff
        newRect.origin.y = newRect.origin.y + 4.0
        super.drawInsertionPoint(in: newRect, color: EditTextView.fontColor, turnedOn: flag)
    }

    override func becomeFirstResponder() -> Bool {
        let shouldBecomeFirstResponder = super.becomeFirstResponder()
        if shouldBecomeFirstResponder && string.isEmpty {
            let paragraphStyle = NSTextStorage.getParagraphStyle()
            typingAttributes[.paragraphStyle] = paragraphStyle
            defaultParagraphStyle = paragraphStyle
        }

        return shouldBecomeFirstResponder
    }

    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(true)
        if let range = selectedRanges[0] as? NSRange, range.length > 0, range != initRange {
            DispatchQueue.main.async {
                self.initRange = range
            }
        }
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        var newInvalidRect = NSRect(origin: invalidRect.origin, size: invalidRect.size)
        newInvalidRect.size.width += caretWidth - 1
        super.setNeedsDisplay(newInvalidRect)
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [] }

    override func mouseDown(with event: NSEvent) {
        guard EditTextView.note != nil else { return }

        guard let container = textContainer, let manager = layoutManager else { return }

        let point = convert(event.locationInWindow, from: nil)
        let properPoint = NSPoint(x: point.x - textContainerInset.width, y: point.y)

        let index = manager.characterIndex(for: properPoint, in: container, fractionOfDistanceBetweenInsertionPoints: nil)

        _ = manager.boundingRect(forGlyphRange: NSRange(location: index, length: 1), in: container)

        super.mouseDown(with: event)

        saveCursorPosition()

        if !UserDefaultsManagement.preview {
            isEditable = true
        }

        if initRange.length > 0 {
            DispatchQueue.main.async {
                self.initRange = NSRange(location: 0, length: 0)
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let viewController = window?.contentViewController as! ViewController
        if !viewController.emptyEditAreaView.isHidden {
            NSCursor.arrow.set()
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let properPoint = NSPoint(x: point.x - textContainerInset.width, y: point.y)

        guard let container = textContainer, let manager = layoutManager else { return }

        let index = manager.characterIndex(for: properPoint, in: container, fractionOfDistanceBetweenInsertionPoints: nil)

        _ = manager.boundingRect(forGlyphRange: NSRange(location: index, length: 1), in: container)

        if UserDefaultsManagement.preview {
            return
        }

        // 给链接在 command 的时候加上一个手
        if NSEvent.modifierFlags.contains(.command) {
            if #available(OSX 10.13, *) {
                linkTextAttributes = [
                    .foregroundColor: NSColor(named: "highlight")!,
                    .cursor: NSCursor.pointingHand
                ]
            }
        } else {
            if #available(OSX 10.13, *) {
                linkTextAttributes = [
                    .foregroundColor: NSColor(named: "highlight")!
                ]
            }
        }

        super.mouseMoved(with: event)
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

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        for menuItem in menu.items {
            if menuItem.identifier?.rawValue == "_searchWithGoogleFromMenu:" ||
                menuItem.identifier?.rawValue == "__NSTextViewContextSubmenuIdentifierSpellingAndGrammar" ||
                menuItem.identifier?.rawValue == "__NSTextViewContextSubmenuIdentifierSubstitutions" ||
                menuItem.identifier?.rawValue == "__NSTextViewContextSubmenuIdentifierTransformations" ||
                menuItem.identifier?.rawValue == "_NS:290" ||
                menuItem.identifier?.rawValue == "_NS:291" ||
                menuItem.identifier?.rawValue == "_NS:328" ||
                menuItem.identifier?.rawValue == "_NS:353"
            {
                menuItem.isHidden = true
            }
        }
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

    // 修复下在剪切地址的时候，链接高亮问题
    override func cut(_ sender: Any?) {
        super.cut(sender)
        fillHighlightLinks()
    }

    override func copy(_ sender: Any?) {
        if selectedRanges.count > 1 {
            let combined = String()
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(combined.trim().removeLastNewLine(), forType: NSPasteboard.PasteboardType.string)
            return
        }

        if selectedRange.length == 0, let paragraphRange = getParagraphRange(), let paragraph = attributedSubstring(forProposedRange: paragraphRange, actualRange: nil) {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(paragraph.string.trim().removeLastNewLine(), forType: NSPasteboard.PasteboardType.string)
            return
        }
        super.copy(sender)
        fillHighlightLinks()
    }

    override func paste(_ sender: Any?) {
        guard let note = EditTextView.note else { return }

        if let clipboard = NSPasteboard.general.string(forType: NSPasteboard.PasteboardType.string), NSPasteboard.general.string(forType: NSPasteboard.PasteboardType.fileURL) == nil {
            EditTextView.shouldForceRescan = true

            let currentRange = selectedRange()
            breakUndoCoalescing()
            insertText(clipboard, replacementRange: currentRange)
            breakUndoCoalescing()
            saveTextStorageContent(to: note)
            fillHighlightLinks()
            return
        }

        if pasteImageFromClipboard(in: note) {
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

            // 防止文件其实是一个文件夹的场景
            if let url = NSURL(from: NSPasteboard.general), let ext = url.pathExtension {
                if !url.isFileURL || ["app", "xcodeproj", "screenflow", "xcworkspace", "bundle", "lproj"].firstIndex(where: { $0 == ext })! > -1 {
                    return
                }
            }

            if let note = EditTextView.note,
               let imageData = textAttachment.fileWrapper?.regularFileContents,
               let path = ImagesProcessor.writeFile(data: imageData, note: note)
            {
                storage.addAttribute(filePathKey, value: path, range: range)
            }
        }
    }

    @IBAction func boldMenu(_ sender: Any) {
        guard let vc = ViewController.shared(),
              let editArea = vc.editArea,
              let note = EditTextView.note,
              !UserDefaultsManagement.preview,
              editArea.hasFocus()
        else { return }

        let formatter = TextFormatter(textView: editArea, note: note)
        formatter.bold()
    }

    @IBAction func italicMenu(_ sender: Any) {
        guard let vc = ViewController.shared(),
              let editArea = vc.editArea,
              let note = EditTextView.note,
              !UserDefaultsManagement.preview,
              editArea.hasFocus()
        else { return }

        let formatter = TextFormatter(textView: editArea, note: note)
        formatter.italic()
    }

    @IBAction func linkMenu(_ sender: Any) {
        guard let vc = ViewController.shared(),
              let editArea = vc.editArea,
              let note = EditTextView.note,
              !UserDefaultsManagement.preview,
              editArea.hasFocus()
        else { return }

        let formatter = TextFormatter(textView: editArea, note: note)
        formatter.link()
    }

    @IBAction func todoMenu(_ sender: Any) {
        guard let vc = ViewController.shared(),
              let editArea = vc.editArea,
              let note = EditTextView.note,
              !UserDefaultsManagement.preview,
              editArea.hasFocus()
        else { return }
        let formatter = TextFormatter(textView: editArea, note: note, shouldScanMarkdown: false)
        formatter.toggleTodo()
    }

    @IBAction func underlineMenu(_ sender: Any) {
        guard let vc = ViewController.shared(),
              let editArea = vc.editArea,
              let note = EditTextView.note,
              !UserDefaultsManagement.preview,
              editArea.hasFocus()
        else { return }

        let formatter = TextFormatter(textView: editArea, note: note)
        formatter.underline()
    }

    @IBAction func deletelineMenu(_ sender: Any) {
        guard let vc = ViewController.shared(),
              let editArea = vc.editArea,
              let note = EditTextView.note,
              !UserDefaultsManagement.preview,
              editArea.hasFocus()
        else { return }

        let formatter = TextFormatter(textView: editArea, note: note)
        formatter.deleteline()
    }

    @IBAction func togglePreview(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }

        vc.togglePreview()
    }

    @IBAction func formatText(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }

        vc.formatText()
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

    func fill(note: Note, highlight: Bool = false, saveTyping: Bool = false, force: Bool = false, needScrollToCursor: Bool = true) {
        let viewController = window?.contentViewController as! ViewController
        viewController.emptyEditAreaView.isHidden = true
        viewController.titleBarView.isHidden = false

        EditTextView.note = note
        UserDefaultsManagement.lastSelectedURL = note.url

        viewController.updateTitle(newTitle: note.getFileName())

        undoManager?.removeAllActions(withTarget: self)

        if let appDelegate = NSApplication.shared.delegate as? AppDelegate,
           let md = appDelegate.mainWindowController
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

        fillHighlightLinks()
        textStorage?.updateParagraphStyle()
        restoreCursorPosition(needScrollToCursor: needScrollToCursor)
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
            viewController.refreshMiaoYanNum()
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
        )
        else {
            super.keyDown(with: event)
            return
        }

        guard let note = EditTextView.note else { return }

        // 简化原有的tab切换逻辑
        if event.keyCode == kVK_Tab, !hasMarkedText() {
            breakUndoCoalescing()
            let formatter = TextFormatter(textView: self, note: note)
            if event.modifierFlags.contains(.shift) {
                formatter.unTab()
            } else {
                formatter.tab()
            }
            saveCursorPosition()
            breakUndoCoalescing()
            return
        }

        if event.keyCode == kVK_Return, !hasMarkedText() {
            breakUndoCoalescing()
            let formatter = TextFormatter(textView: self, note: note, shouldScanMarkdown: false)
            // 对于有shift的直接回车
            if event.modifierFlags.contains(.shift) {
                insertNewline(nil)
            } else {
                formatter.newLine()
            }
            breakUndoCoalescing()
            fillHighlightLinks()
            saveCursorPosition()
            return
        }

        if event.keyCode == kVK_Delete, event.modifierFlags.contains(.option) {
            deleteWordBackward(nil)
            return
        }

        super.keyDown(with: event)

        fillHighlightLinks()
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

    func restoreCursorPosition(needScrollToCursor: Bool = true) {
        guard let storage = textStorage else { return }

        guard UserDefaultsManagement.restoreCursorPosition else {
            setSelectedRange(NSMakeRange(0, 0))
            return
        }

        if let position = EditTextView.note?.getCursorPosition(), position <= storage.length {
            setSelectedRange(NSMakeRange(position, 0))
            if needScrollToCursor {
                scrollToCursor()
            }
        }
    }

    func saveTextStorageContent(to note: Note) {
        guard let storage = textStorage else { return }

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

            insertText(mutable, replacementRange: NSRange(location: caretLocation, length: 0))
            storage.sizeAttachmentImages()

            DispatchQueue.main.async {
                self.setSelectedRange(NSRange(location: caretLocation, length: mutable.length))
            }

            return true
        }

        if let data = board.data(forType: NSPasteboard.PasteboardType(rawValue: "attributedText")), let attributedText = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSMutableAttributedString.self, from: data) {
            let dropPoint = convert(sender.draggingLocation, from: nil)
            let caretLocation = characterIndexForInsertion(at: dropPoint)

            let filePathKey = NSAttributedString.Key(rawValue: "com.tw93.miaoyan.image.path")
            let titleKey = NSAttributedString.Key(rawValue: "com.tw93.miaoyan.image.title")
            let positionKey = NSAttributedString.Key(rawValue: "com.tw93.miaoyan.image.position")

            guard
                let path = attributedText.attribute(filePathKey, at: 0, effectiveRange: nil) as? String,
                let title = attributedText.attribute(titleKey, at: 0, effectiveRange: nil) as? String,
                let position = attributedText.attribute(positionKey, at: 0, effectiveRange: nil) as? Int
            else { return false }

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
            let offset = 0

            unLoadImages(note: note)

            for url in urls {
                do {
                    data = try Data(contentsOf: url)
                } catch {
                    return false
                }

                guard let filePath = ImagesProcessor.writeFile(data: data, url: url, note: note) else { return false }

                let insertRange = NSRange(location: caretLocation + offset, length: 0)
                insertText("![](\(filePath))", replacementRange: insertRange)
                insertNewline(nil)
                insertNewline(nil)
            }

            if let storage = textStorage {
                NotesTextProcessor.highlightMarkdown(attributedString: storage, note: note)
                saveTextStorageContent(to: note)
                note.save()
            }
            viewDelegate?.notesTableView.reloadRow(note: note)

            return true
        }

        return false
    }

    public func unLoadImages(note: Note) {
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
        let f = TextFormatter(textView: self, note: note, shouldScanMarkdown: true)
        EditTextView.shouldForceRescan = true
        f.unTab()
    }

    @IBAction func shiftRight(_ sender: Any) {
        guard let note = EditTextView.note else { return }
        let f = TextFormatter(textView: self, note: note, shouldScanMarkdown: true)
        EditTextView.shouldForceRescan = true
        f.tab()
    }

    @IBAction func insertFileOrImage(_ sender: Any) {
        guard let note = EditTextView.note else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = true
        panel.begin { result in
            if result == NSApplication.ModalResponse.OK {
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

    private func getTextFormatter() -> TextFormatter? {
        guard let note = EditTextView.note else { return nil }

        return TextFormatter(textView: self, note: note)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let selected = attributedSubstring(forProposedRange: selectedRange(), actualRange: nil) else { return .generic }

        let attributedString = NSMutableAttributedString(attributedString: selected)
        let positionKey = NSAttributedString.Key(rawValue: "com.tw93.miaoyan.image.position")
        attributedString.addAttribute(positionKey, value: selectedRange().location, range: NSRange(0..<1))

        if let data = try? NSKeyedArchiver.archivedData(withRootObject: attributedString, requiringSecureCoding: false) {
            let type = NSPasteboard.PasteboardType(rawValue: "attributedText")
            let board = sender.draggingPasteboard
            board.setData(data, forType: type)
        }

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
            // 只有 command 加点击的时候才外跳
            if !NSEvent.modifierFlags.contains(.command) {
                setSelectedRange(NSRange(location: charIndex, length: 0))
                saveCursorPosition()
                return
            }

            // String 外跳
            if let link = link as? String, let url = URL(string: link) {
                _ = try? NSWorkspace.shared.open(url, options: .withoutActivation, configuration: [:])
                return
            }

            // URL 链接外跳
            if let link = link as? URL {
                _ = try? NSWorkspace.shared.open(link, options: .withoutActivation, configuration: [:])
                return
            }

            super.clicked(onLink: link, at: charIndex)
            return
        }

        let url = URL(fileURLWithPath: link as! String)

        NSWorkspace.shared.open(url)
    }

    override func viewDidChangeEffectiveAppearance() {
        guard let note = EditTextView.note else { return }
        guard let vc = ViewController.shared() else { return }
        UserDataService.instance.isDark = effectiveAppearance.isDark

        NotesTextProcessor.hl = nil
        NotesTextProcessor.highlight(note: note)

        // 用于自动模式下切换时候的效果
        if UserDefaultsManagement.preview {
            vc.disablePreview()
            vc.enablePreview()
        }

        viewDelegate?.refillEditArea()
    }

    public func fillHighlightLinks() {
        guard let storage = textStorage else { return }
        let range = NSRange(0..<storage.length)
        let processor = NotesTextProcessor(storage: storage, range: range)
        processor.highlightLinks()
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

    func run(_ cmd: String) -> String? {
        let pipe = Pipe()
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = ["-c", String(format: "%@", cmd)]
        process.standardOutput = pipe
        let fileHandle = pipe.fileHandleForReading
        process.launch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            process.terminate()
        }
        process.waitUntilExit()
        return String(data: fileHandle.readDataToEndOfFile(), encoding: .utf8)
    }

    func postToPicGo(imagePath: String, completion: @escaping (Any?, Error?) -> Void) {
        let parameters: [String: [String]] = [
            "list": [imagePath]
        ]
        AF.request("http://127.0.0.1:36677/upload", method: .post, parameters: parameters, encoder: JSONParameterEncoder.default).response { response in
            switch response.result {
            case .success:
                let json = JSON(response.value as Any)
                let result = json["result"][0].stringValue
                if !result.isEmpty {
                    completion(result, nil)
                } else {
                    completion(nil, nil)
                }

            case .failure:
                completion(nil, nil)
            }
        }
    }

    func deleteImage(tempPath: URL) {
        do {
            guard let resultingItemUrl = Storage.sharedInstance().trashItem(url: tempPath) else { return }
            try FileManager.default.moveItem(at: tempPath, to: resultingItemUrl)
        } catch {
            print(error)
        }
    }

    private func saveClipboard(data: Data, note: Note, ext: String? = nil, url: URL? = nil) {
        guard let vc = ViewController.shared() else { return }
        if let path = ImagesProcessor.writeFile(data: data, url: url, note: note, ext: ext) {
            var newLineImage = NSAttributedString(string: "![](\(path))")
            let imagePath = "\(note.project.url.path)\(path)"
            let tempPath = URL(fileURLWithPath: imagePath)
            let picType = UserDefaultsManagement.defaultPicUpload
            if picType == "PicGo" {
                vc.toastUpload(status: true)
                postToPicGo(imagePath: imagePath) { result, error in
                    if let result = result {
                        newLineImage = NSAttributedString(string: "![](\(result))")
                        self.deleteImage(tempPath: tempPath)
                    } else if let error = error {
                        vc.toastUpload(status: false)
                        print("error: \(error.localizedDescription)")
                    } else {
                        vc.toastUpload(status: false)
                    }
                    self.breakUndoCoalescing()
                    self.insertText(newLineImage, replacementRange: self.selectedRange())
                    self.breakUndoCoalescing()
                }
            } else {
                if picType == "uPic" || picType == "Picsee" {
                    vc.toastUpload(status: true)
                    let runList = run("/Applications/\(picType).app/Contents/MacOS/\(picType) -o url -u \(tempPath)")
                    let imageDesc = runList?.components(separatedBy: "\n") ?? []

                    if imageDesc.count > 3 {
                        let imagePath = imageDesc[4]
                        newLineImage = NSAttributedString(string: "![](\(imagePath))")
                        deleteImage(tempPath: tempPath)
                    } else {
                        vc.toastUpload(status: false)
                    }
                }
                breakUndoCoalescing()
                insertText(newLineImage, replacementRange: selectedRange())
                breakUndoCoalescing()
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

    @available(OSX 10.12.2, *)
    override func makeTouchBar() -> NSTouchBar? {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = []
        return touchBar
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
