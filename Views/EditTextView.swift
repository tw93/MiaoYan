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
    private var linkHighlightTimer: Timer?
    private weak var cachedViewController: ViewController?
    var isHighlighted: Bool = false
    let storage = Storage.sharedInstance()
    let caretWidth: CGFloat = 1
    var initRange = NSRange(location: 0, length: 0)
    public var timer: Timer?
    public var markdownView: MPreviewView?
    public static var imagesLoaderQueue = OperationQueue()
    private var imagePreviewManager: ImagePreviewManager?
    private var clipboardManager: ClipboardManager?
    private var menuManager: EditorMenuManager?
    public static var fontColor: NSColor {
        if UserDefaultsManagement.appearanceType != AppearanceType.Custom, #available(OSX 10.13, *) {
            NSColor(named: "mainText")!
        } else {
            UserDefaultsManagement.fontColor
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
        imagePreviewManager = ImagePreviewManager(textView: self)
        clipboardManager = ClipboardManager(textView: self)
        menuManager = EditorMenuManager(textView: self)
    }
    deinit {
        linkHighlightTimer?.invalidate()
        linkHighlightTimer = nil
    }
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var newRect = NSRect(origin: rect.origin, size: rect.size)
        newRect.size.width = caretWidth
        var diff = 4.0
        if let range = getParagraphRange(),
            range.upperBound != textStorage?.length
                || (range.upperBound == textStorage?.length
                    && textStorage?.string.last == "\n"
                    && selectedRange().location != textStorage?.length)
        {
            diff = 6.0
        }
        newRect.size.height = newRect.size.height - diff
        newRect.origin.y = newRect.origin.y + 4.0
        super.drawInsertionPoint(in: newRect, color: EditTextView.fontColor, turnedOn: flag)
    }
    override func becomeFirstResponder() -> Bool {
        let shouldBecomeFirstResponder = super.becomeFirstResponder()
        if shouldBecomeFirstResponder, string.isEmpty {
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
        imagePreviewManager?.handleMouseClick(at: event.locationInWindow)
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
        guard let viewController = window?.contentViewController as? ViewController else {
            imagePreviewManager?.hideImagePreview()
            return
        }
        if !viewController.emptyEditAreaView.isHidden {
            NSCursor.arrow.set()
            imagePreviewManager?.hideImagePreview()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let properPoint = NSPoint(x: point.x - textContainerInset.width, y: point.y)
        guard let container = textContainer, let manager = layoutManager else {
            imagePreviewManager?.hideImagePreview()
            return
        }
        let index = manager.characterIndex(for: properPoint, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        _ = manager.boundingRect(forGlyphRange: NSRange(location: index, length: 1), in: container)
        if UserDefaultsManagement.preview {
            imagePreviewManager?.hideImagePreview()
            return
        }
        imagePreviewManager?.handleImageLinkHover(at: index, mousePoint: event.locationInWindow)
        if NSEvent.modifierFlags.contains(.command) {
            if #available(OSX 10.13, *) {
                linkTextAttributes = [
                    .foregroundColor: NSColor(named: "highlight")!,
                    .cursor: NSCursor.pointingHand,
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
            if menuItem.identifier?.rawValue == "_searchWithGoogleFromMenu:" || menuItem.identifier?.rawValue == "__NSTextViewContextSubmenuIdentifierSpellingAndGrammar"
                || menuItem.identifier?.rawValue == "__NSTextViewContextSubmenuIdentifierSubstitutions" || menuItem.identifier?.rawValue == "__NSTextViewContextSubmenuIdentifierTransformations" || menuItem.identifier?.rawValue == "_NS:290"
                || menuItem.identifier?.rawValue == "_NS:291" || menuItem.identifier?.rawValue == "_NS:328" || menuItem.identifier?.rawValue == "_NS:353"
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
            if let rtfd = try? richString.data(from: NSRange(location: 0, length: richString.length), documentAttributes: [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtfd]) {
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
    override func cut(_ sender: Any?) {
        super.cut(sender)
        fillHighlightLinks()
    }
    override func copy(_ sender: Any?) {
        if let handled = clipboardManager?.handleCopy(), handled {
            return
        }
        super.copy(sender)
        fillHighlightLinks()
    }
    override func paste(_ sender: Any?) {
        guard let note = EditTextView.note else { return }
        if let handled = clipboardManager?.handlePaste(in: note), handled {
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
            if let url = NSURL(from: NSPasteboard.general), let ext = url.pathExtension {
                let excludedExtensions = ["app", "xcodeproj", "screenflow", "xcworkspace", "bundle", "lproj"]
                if !url.isFileURL || excludedExtensions.contains(ext) {
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
        menuManager?.performFormattingAction(.bold)
    }
    @IBAction func italicMenu(_ sender: Any) {
        menuManager?.performFormattingAction(.italic)
    }
    @IBAction func linkMenu(_ sender: Any) {
        menuManager?.performFormattingAction(.link)
    }
    @IBAction func todoMenu(_ sender: Any) {
        menuManager?.performFormattingAction(.todo)
    }
    @IBAction func underlineMenu(_ sender: Any) {
        menuManager?.performFormattingAction(.underline)
    }
    @IBAction func deletelineMenu(_ sender: Any) {
        menuManager?.performFormattingAction(.deleteline)
    }
    @IBAction func togglePreview(_ sender: Any) {
        menuManager?.togglePreview()
    }
    @IBAction func formatText(_ sender: Any) {
        menuManager?.formatText()
    }
    @IBAction func togglePresentation(_ sender: Any) {
        menuManager?.togglePresentation()
    }
    func getSelectedNote() -> Note? {
        return getViewController()?.notesTableView.getSelectedNote()
    }
    private func getViewController() -> ViewController? {
        if let cached = cachedViewController {
            return cached
        }
        let vc = ViewController.shared()
        cachedViewController = vc
        return vc
    }
    public func isEditable(note: Note) -> Bool {
        if UserDefaultsManagement.preview {
            return false
        }
        return true
    }
    func fill(note: Note, highlight: Bool = false, saveTyping: Bool = false, force: Bool = false, needScrollToCursor: Bool = true) {
        guard let viewController = window?.contentViewController as? ViewController else {
            return
        }
        viewController.emptyEditAreaView.isHidden = true
        // Only show title components if not in PPT mode
        if !UserDefaultsManagement.magicPPT {
            viewController.titleBarView.isHidden = false
            viewController.titleLabel.isHidden = false
        }
        EditTextView.note = note
        UserDefaultsManagement.lastSelectedURL = note.url
        viewController.updateTitle(newTitle: note.getTitleWithoutLabel())
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
        if UserDefaultsManagement.preview || UserDefaultsManagement.magicPPT {
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
        markdownView?.isHidden = true
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
    public func clear() {
        textStorage?.setAttributedString(NSAttributedString())
        markdownView?.isHidden = true
        imagePreviewManager?.hideImagePreview()
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
    // MARK: - Removed Large Methods
    // Complex logic moved to dedicated manager classes:
    // - ImagePreviewManager: Image preview functionality
    // - ClipboardManager: Clipboard operations
    // - EditorMenuManager: Menu operations
    func getParagraphRange() -> NSRange? {
        guard let vc = getViewController(),
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
    // MARK: - Link Highlighting Performance Optimization
    private func shouldTriggerLinkHighlight(for event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_Space, kVK_Return, kVK_Tab:
            return true
        case kVK_Delete, kVK_ForwardDelete:
            return true
        default:
            if let characters = event.characters {
                return characters.contains(where: { "]).>:\"'".contains($0) })
            }
            return false
        }
    }
    private func scheduleLinkHighlight(range: NSRange? = nil, immediate: Bool = false) {
        linkHighlightTimer?.invalidate()
        if immediate {
            if let targetRange = range {
                fillHighlightLinks(range: targetRange)
            } else {
                fillHighlightLinks()
            }
        } else {
            linkHighlightTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    if let targetRange = range {
                        self?.fillHighlightLinks(range: targetRange)
                    } else {
                        self?.fillHighlightLinks()
                    }
                }
            }
        }
    }
    func restoreCursorPosition(needScrollToCursor: Bool = true) {
        guard let storage = textStorage else { return }
        guard UserDefaultsManagement.restoreCursorPosition else {
            setSelectedRange(NSRange(location: 0, length: 0))
            return
        }
        if let position = EditTextView.note?.getCursorPosition(),
            position >= 0 && position <= storage.length
        {
            setSelectedRange(NSRange(location: position, length: 0))
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
        guard let note = EditTextView.note, let storage = textStorage else { return false }
        let availableTypes = board.types ?? []
        if availableTypes.contains(.rtfd),
            let data = board.data(forType: .rtfd),
            let text = NSAttributedString(rtfd: data, documentAttributes: nil),
            text.length > 0, range.length > 0
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
        let attributedTextType = NSPasteboard.PasteboardType(rawValue: "attributedText")
        if availableTypes.contains(attributedTextType),
            let data = board.data(forType: attributedTextType),
            let attributedText = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSMutableAttributedString.self, from: data)
        {
            return handleImageDrop(attributedText: attributedText, sender: sender, note: note, storage: storage)
        }
        if let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            return handleFileURLsDrop(urls: urls, sender: sender, note: note, storage: storage)
        }
        return false
    }
    private func handleImageDrop(attributedText: NSMutableAttributedString, sender: NSDraggingInfo, note: Note, storage: NSTextStorage) -> Bool {
        let dropPoint = convert(sender.draggingLocation, from: nil)
        let caretLocation = characterIndexForInsertion(at: dropPoint)
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
        let locationDiff = max(0, position > caretLocation ? caretLocation : caretLocation - 1)
        guard locationDiff < storage.length else { return false }
        let attachment = NoteAttachment(title: title, path: path, url: imageUrl, cache: cacheUrl, invalidateRange: NSRange(location: locationDiff, length: 1))
        guard let attachmentText = attachment.getAttributedString() else { return false }
        textStorage?.deleteCharacters(in: NSRange(location: position, length: 1))
        textStorage?.replaceCharacters(in: NSRange(location: locationDiff, length: 0), with: attachmentText)
        unLoadImages(note: note)
        setSelectedRange(NSRange(location: caretLocation, length: 0))
        return true
    }
    private func handleFileURLsDrop(urls: [URL], sender: NSDraggingInfo, note: Note, storage: NSTextStorage) -> Bool {
        let dropPoint = convert(sender.draggingLocation, from: nil)
        let caretLocation = characterIndexForInsertion(at: dropPoint)
        unLoadImages(note: note)
        var successCount = 0
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                let filePath = ImagesProcessor.writeFile(data: data, url: url, note: note)
            else {
                continue
            }
            let insertRange = NSRange(location: caretLocation + successCount * 2, length: 0)
            insertText("![](\(filePath))", replacementRange: insertRange)
            if url != urls.last {
                insertNewline(nil)
                insertNewline(nil)
            }
            successCount += 1
        }
        guard successCount > 0 else { return false }
        NotesTextProcessor.highlightMarkdown(attributedString: storage, note: note)
        saveTextStorageContent(to: note)
        note.save()
        viewDelegate?.notesTableView.reloadRow(note: note)
        return true
    }
    public func unLoadImages(note: Note) {
        note.save(attributed: attributedString())
    }
    func getSearchText() -> String {
        guard let search = getViewController()?.search else { return "" }
        if let editor = search.currentEditor(), editor.selectedRange.length > 0 {
            let searchString = search.stringValue
            let endIndex = min(editor.selectedRange.location, searchString.count)
            return String(searchString.prefix(endIndex))
        }
        return search.stringValue
    }
    public func scrollToCursor() {
        let cursorRange = NSRange(location: selectedRange().location, length: 0)
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
        menuManager?.insertFileOrImage()
    }
    @IBAction func insertCodeBlock(_ sender: NSButton) {
        menuManager?.insertCodeBlock()
    }
    @IBAction func insertCodeSpan(_ sender: NSMenuItem) {
        menuManager?.insertCodeSpan()
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
        let range = NSRange(location: charIndex, length: 1)
        let char = attributedSubstring(forProposedRange: range, actualRange: nil)
        if char?.attribute(.attachment, at: 0, effectiveRange: nil) == nil {
            if !NSEvent.modifierFlags.contains(.command) {
                setSelectedRange(NSRange(location: charIndex, length: 0))
                saveCursorPosition()
                return
            }
            if let link = link as? String, let url = URL(string: link) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.open(url, configuration: config)
                return
            }
            if let link = link as? URL {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.open(link, configuration: config)
                return
            }
            super.clicked(onLink: link, at: charIndex)
            return
        }
        guard let linkString = link as? String else { return }
        let url = URL(fileURLWithPath: linkString)
        NSWorkspace.shared.open(url)
    }
    override func viewDidChangeEffectiveAppearance() {
        guard let note = EditTextView.note else { return }
        guard let vc = getViewController() else { return }
        UserDataService.instance.isDark = effectiveAppearance.isDark
        NotesTextProcessor.hl = nil
        NotesTextProcessor.highlight(note: note)
        if UserDefaultsManagement.preview {
            vc.disablePreview()
            vc.enablePreview()
        }
        viewDelegate?.refillEditArea()
    }
    public func fillHighlightLinks(range: NSRange? = nil) {
        guard let storage = textStorage else { return }
        let targetRange = range ?? NSRange(0..<storage.length)
        let processor = NotesTextProcessor(storage: storage, range: targetRange)
        processor.highlightLinks()
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
            if value is NSTextAttachment, storage.attribute(.todo, at: range.location, effectiveRange: nil) == nil {
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
        if !removedImages.isEmpty {
            note.undoManager.beginUndoGrouping()
            note.undoManager.setActionName(NSLocalizedString("Delete Images", comment: "Undo action name"))
            note.undoManager.registerUndo(withTarget: self, selector: #selector(unDeleteImages), object: removedImages)
            note.undoManager.endUndoGrouping()
        }
    }
    @objc public func unDeleteImages(_ urls: [URL: URL]) {
        guard let note = EditTextView.note else { return }
        note.undoManager.beginUndoGrouping()
        note.undoManager.setActionName(NSLocalizedString("Restore Images", comment: "Undo action name"))
        var restoredImages = [URL: URL]()
        for (src, dst) in urls {
            do {
                try FileManager.default.moveItem(at: src, to: dst)
                restoredImages[dst] = src
            } catch {
                print(error)
            }
        }
        if !restoredImages.isEmpty {
            note.undoManager.registerUndo(withTarget: self, selector: #selector(deleteRestoredImages), object: restoredImages)
        }
        note.undoManager.endUndoGrouping()
    }
    @objc private func deleteRestoredImages(_ urls: [URL: URL]) {
        guard let note = EditTextView.note else { return }
        note.undoManager.beginUndoGrouping()
        note.undoManager.setActionName(NSLocalizedString("Delete Images", comment: "Undo action name"))
        var deletedImages = [URL: URL]()
        for (src, _) in urls {
            do {
                guard let resultingItemUrl = Storage.sharedInstance().trashItem(url: src) else { continue }
                try FileManager.default.moveItem(at: src, to: resultingItemUrl)
                deletedImages[resultingItemUrl] = src
            } catch {
                print(error)
            }
        }
        if !deletedImages.isEmpty {
            note.undoManager.registerUndo(withTarget: self, selector: #selector(unDeleteImages), object: deletedImages)
        }
        note.undoManager.endUndoGrouping()
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
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        imagePreviewManager?.hideImagePreview()
    }
    override func mouseDragged(with event: NSEvent) {
        imagePreviewManager?.hideImagePreview()
        super.mouseDragged(with: event)
    }
    override func keyDown(with event: NSEvent) {
        imagePreviewManager?.hideImagePreview()
        guard
            !(event.modifierFlags.contains(.shift)
                && [
                    kVK_UpArrow,
                    kVK_DownArrow,
                    kVK_LeftArrow,
                    kVK_RightArrow,
                ].contains(Int(event.keyCode)))
        else {
            super.keyDown(with: event)
            return
        }
        guard let note = EditTextView.note else { return }
        if event.keyCode == kVK_Tab, !hasMarkedText() {
            breakUndoCoalescing()
            let formatter = TextFormatter(textView: self, note: note)
            if event.modifierFlags.contains(.shift) {
                formatter.unTab()
            } else {
                formatter.tab()
            }
            saveCursorPosition()
            return
        }
        if event.keyCode == kVK_Return, !hasMarkedText() {
            breakUndoCoalescing()
            let formatter = TextFormatter(textView: self, note: note, shouldScanMarkdown: false)
            if event.modifierFlags.contains(.shift) {
                insertNewline(nil)
            } else {
                formatter.newLine()
            }
            fillHighlightLinks()
            saveCursorPosition()
            return
        }
        if event.keyCode == kVK_Delete, event.modifierFlags.contains(.option) {
            deleteWordBackward(nil)
            return
        }
        super.keyDown(with: event)
        if shouldTriggerLinkHighlight(for: event) {
            if let paragraphRange = getParagraphRange() {
                scheduleLinkHighlight(range: paragraphRange)
            } else {
                scheduleLinkHighlight()
            }
        }
        saveCursorPosition()
    }
}
