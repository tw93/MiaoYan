import Carbon.HIToolbox
import Cocoa
import Highlightr
import SwiftyJSON

// Configuration options for EditTextView fill operations
struct FillOptions {
    let highlight: Bool
    let saveTyping: Bool
    let force: Bool
    let needScrollToCursor: Bool

    // Common presets
    static let `default` = FillOptions(highlight: false, saveTyping: false, force: false, needScrollToCursor: true)
    static let forced = FillOptions(highlight: true, saveTyping: false, force: true, needScrollToCursor: true)
    static let silent = FillOptions(highlight: true, saveTyping: false, force: true, needScrollToCursor: false)
}

@MainActor
class EditTextView: NSTextView, @preconcurrency NSTextFinderClient {
    public static var note: Note?
    public static var isBusyProcessing: Bool = false
    public static var shouldForceRescan: Bool = false
    public static var lastRemoved: String?
    public var viewDelegate: ViewController?
    nonisolated(unsafe) private var linkHighlightTimer: Timer?
    nonisolated(unsafe) private weak var cachedViewController: ViewController?
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
    public static var fontColor: NSColor { Theme.textColor }
    override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        return NSPoint(x: origin.x, y: origin.y - 7)
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated { [self] in
            EditTextView.imagesLoaderQueue.maxConcurrentOperationCount = 3
            EditTextView.imagesLoaderQueue.qualityOfService = .userInteractive
            imagePreviewManager = ImagePreviewManager(textView: self)
            clipboardManager = ClipboardManager(textView: self)
            menuManager = EditorMenuManager(textView: self)
        }
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
        newRect.size.height -= diff
        newRect.origin.y += 4.0
        super.drawInsertionPoint(in: newRect, color: EditTextView.fontColor, turnedOn: flag)
    }

    override func becomeFirstResponder() -> Bool {
        let shouldBecomeFirstResponder = super.becomeFirstResponder()
        if shouldBecomeFirstResponder, string.isEmpty {
            let paragraphStyle = NSTextStorage.getParagraphStyle()
            typingAttributes[.paragraphStyle] = paragraphStyle
            defaultParagraphStyle = paragraphStyle
            // Ensure letter spacing is applied to typing attributes
            if UserDefaultsManagement.editorLetterSpacing != 0 {
                typingAttributes[.kern] = UserDefaultsManagement.editorLetterSpacing
            }
        }
        return shouldBecomeFirstResponder
    }

    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(true)
        if let range = selectedRanges[0] as? NSRange, range.length > 0, range != initRange {
            self.initRange = range
        }
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        var newInvalidRect = NSRect(origin: invalidRect.origin, size: invalidRect.size)
        newInvalidRect.size.width += caretWidth - 1
        super.setNeedsDisplay(newInvalidRect)
    }

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
            self.initRange = NSRange(location: 0, length: 0)
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
            linkTextAttributes = [
                .foregroundColor: Theme.highlightColor,
                .cursor: NSCursor.pointingHand,
            ]
        } else {
            linkTextAttributes = [
                .foregroundColor: Theme.highlightColor
            ]
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
        [NSPasteboard.PasteboardType.string]
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

    // MARK: - Quick Input Menu Actions
    @IBAction func insertTimeShortcut(_ sender: Any) {
        insertShortcutText("time")
    }

    @IBAction func insertTableShortcut(_ sender: Any) {
        insertShortcutText("table")
    }

    @IBAction func insertImgShortcut(_ sender: Any) {
        insertShortcutText("img")
    }

    @IBAction func insertVideoShortcut(_ sender: Any) {
        insertShortcutText("video")
    }

    @IBAction func insertMarkmapShortcut(_ sender: Any) {
        insertShortcutText("markmap")
    }

    @IBAction func insertMermaidShortcut(_ sender: Any) {
        insertShortcutText("mermaid")
    }

    @IBAction func insertPlantumlShortcut(_ sender: Any) {
        insertShortcutText("plantuml")
    }

    @IBAction func insertFoldShortcut(_ sender: Any) {
        insertShortcutText("fold")
    }

    @IBAction func insertTaskShortcut(_ sender: Any) {
        insertShortcutText("task")
    }

    private func insertShortcutText(_ shortcut: String) {
        guard EditTextView.note != nil else { return }
        window?.makeFirstResponder(self)

        let range = selectedRange()
        let text = "/\(shortcut)"

        // Use the standard text replacement method that preserves formatting
        if shouldChangeText(in: range, replacementString: text) {
            // Get current typing attributes to maintain formatting
            let attributes = typingAttributes
            let attributedText = NSAttributedString(string: text, attributes: attributes)

            textStorage?.replaceCharacters(in: range, with: attributedText)
            didChangeText()

            // Update cursor position
            let newPosition = range.location + text.count
            setSelectedRange(NSRange(location: newPosition, length: 0))
        }
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

    // New fill method using configuration object
    func fill(note: Note, options: FillOptions = .default) {
        guard let viewController = window?.contentViewController as? ViewController else {
            return
        }

        // Prevent filling during note creation to avoid content flashing
        if UserDataService.instance.shouldBlockEditAreaUpdate(forceUpdate: options.force) {
            return
        }

        // Call the internal implementation
        _performFill(note: note, options: options, viewController: viewController)
    }

    // Internal implementation method
    private func _performFill(note: Note, options: FillOptions, viewController: ViewController) {
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
        if !options.saveTyping {
            typingAttributes.removeAll()
            typingAttributes[.font] = UserDefaultsManagement.noteFont
            // Apply letter spacing to typing attributes
            if UserDefaultsManagement.editorLetterSpacing != 0 {
                typingAttributes[.kern] = UserDefaultsManagement.editorLetterSpacing
            }
        }
        // Render preview content in preview, PPT, or presentation modes
        if UserDefaultsManagement.preview || UserDefaultsManagement.magicPPT || UserDefaultsManagement.presentation {
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
                markdownView?.load(note: note, force: options.force)
                /// Ensure it is visible in case it was hidden by clear() during sidebar switch
                markdownView?.isHidden = false
                markdownView?.alphaValue = 1.0
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
        if options.highlight {
            let search = getSearchText()
            let processor = NotesTextProcessor(storage: storage)
            processor.highlightKeyword(search: search)
            isHighlighted = true
        }
        fillHighlightLinks()
        textStorage?.updateParagraphStyle()
        // Apply letter spacing after all formatting is complete
        if let storage = textStorage {
            storage.applyEditorLetterSpacing()
        }
        restoreCursorPosition(needScrollToCursor: options.needScrollToCursor)
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

    // MARK: - Editor Utility Helpers
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
                typingAttributes[.foregroundColor] = Theme.textColor
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

        let delay: TimeInterval = immediate ? 0 : 0.05

        linkHighlightTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let storage = self.textStorage else { return }

                // Always use full range for safety - recalculate at execution time
                let safeRange = NSRange(0..<storage.length)
                let processor = NotesTextProcessor(storage: storage, range: safeRange)
                processor.highlightLinks()
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

        if UserDefaultsManagement.appearanceType == .System {
            UserDataService.instance.isDark = effectiveAppearance.isDark
        }

        NotesTextProcessor.hl = nil
        NotesTextProcessor.highlight(note: note)

        if UserDefaultsManagement.preview && UserDefaultsManagement.appearanceType == .System {
            vc.disablePreview()
            vc.enablePreview()
        }
        viewDelegate?.refillEditArea()
    }

    public func fillHighlightLinks(range: NSRange? = nil) {
        scheduleLinkHighlight(immediate: true)
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
                            AppDelegate.trackError(error, context: "EditTextView.savePasteboard")
                        }
                    }
                }
            }
        }
        if !removedImages.isEmpty {
            note.undoManager.beginUndoGrouping()
            note.undoManager.setActionName(I18n.str("Delete Images"))
            note.undoManager.registerUndo(withTarget: self, selector: #selector(unDeleteImages), object: removedImages)
            note.undoManager.endUndoGrouping()
        }
    }

    @objc public func unDeleteImages(_ urls: [URL: URL]) {
        guard let note = EditTextView.note else { return }
        note.undoManager.beginUndoGrouping()
        note.undoManager.setActionName(I18n.str("Restore Images"))
        var restoredImages = [URL: URL]()
        for (src, dst) in urls {
            do {
                try FileManager.default.moveItem(at: src, to: dst)
                restoredImages[dst] = src
            } catch {
                AppDelegate.trackError(error, context: "EditTextView.insertMarkdown")
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
        note.undoManager.setActionName(I18n.str("Delete Images"))
        var deletedImages = [URL: URL]()
        for (src, _) in urls {
            do {
                guard let resultingItemUrl = Storage.sharedInstance().trashItem(url: src) else { continue }
                try FileManager.default.moveItem(at: src, to: resultingItemUrl)
                deletedImages[resultingItemUrl] = src
            } catch {
                AppDelegate.trackError(error, context: "EditTextView.handlePaste")
            }
        }
        if !deletedImages.isEmpty {
            note.undoManager.registerUndo(withTarget: self, selector: #selector(unDeleteImages), object: deletedImages)
        }
        note.undoManager.endUndoGrouping()
    }

    override func makeTouchBar() -> NSTouchBar? {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = []
        return touchBar
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        let editTitle = I18n.str("Edit Link…")
        if let editLink = menu?.item(withTitle: editTitle) {
            menu?.removeItem(editLink)
        }
        let removeTitle = I18n.str("Remove Link")
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

            // Check for shortcut expansion first
            if !event.modifierFlags.contains(.shift), handleShortcutExpansion() {
                saveCursorPosition()
                return
            }

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

        if event.keyCode == kVK_Escape {
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

    override func keyUp(with event: NSEvent) {
        if event.keyCode == kVK_Escape {
            guard let vc = window?.contentViewController as? ViewController else {
                super.keyUp(with: event)
                return
            }
            vc.notesTableView.window?.makeFirstResponder(vc.notesTableView)
            if let selectedNote = EditTextView.note,
                let noteIndex = vc.notesTableView.getIndex(selectedNote)
            {
                vc.notesTableView.selectRowIndexes([noteIndex], byExtendingSelection: false)
                vc.notesTableView.scrollRowToVisible(noteIndex)
            }
            return
        }
        super.keyUp(with: event)
    }

    // MARK: - Preview Management
    public func recreatePreviewView() {
        guard let viewController = ViewController.shared() else { return }

        // Remove existing preview view if it exists
        if let existingView = markdownView {
            existingView.removeFromSuperview()
            markdownView = nil
        }

        // Recreate preview view if in preview mode
        if UserDefaultsManagement.preview || UserDefaultsManagement.magicPPT || UserDefaultsManagement.presentation,
            let currentNote = EditTextView.note
        {
            let frame = viewController.editAreaScroll.bounds
            markdownView = MPreviewView(frame: frame, note: currentNote, closure: {})
            if let newView = markdownView {
                viewController.editAreaScroll.addSubview(newView)
                newView.isHidden = false
                newView.alphaValue = 1.0
            }
        }
    }

    // MARK: - Shortcut Expansion
    private func handleShortcutExpansion() -> Bool {
        guard let storage = textStorage else { return false }

        let range = selectedRange()
        let text = storage.string as NSString

        // Get the current line
        let lineRange = text.lineRange(for: range)
        let beforeCursor = text.substring(with: NSRange(location: lineRange.location, length: range.location - lineRange.location))

        // Extract shortcut if present
        guard let shortcut = extractShortcut(from: beforeCursor) else { return false }

        return expandShortcut(shortcut, at: range)
    }

    private func extractShortcut(from text: String) -> String? {
        // Simple suffix matching - more efficient than regex for this case
        guard text.hasSuffix("/") == false else { return nil }

        let components = text.components(separatedBy: "/")
        guard let lastComponent = components.last,
            !lastComponent.isEmpty,
            lastComponent.allSatisfy({ $0.isLetter || $0.isNumber })
        else {
            return nil
        }

        return lastComponent
    }

    private func expandShortcut(_ shortcut: String, at range: NSRange) -> Bool {
        guard let template = ShortcutTemplateManager.shared.getTemplate(for: shortcut),
            let textStorage = textStorage
        else {
            return false
        }

        // Calculate the range to replace (including the "/" + shortcut)
        let replaceStart = range.location - shortcut.count - 1  // -1 for "/"
        let replaceLength = shortcut.count + 1

        // Bounds checking
        guard replaceStart >= 0,
            replaceStart + replaceLength <= textStorage.length
        else {
            return false
        }

        let replaceRange = NSRange(location: replaceStart, length: replaceLength)

        // Perform text replacement
        replaceText(template.content, in: replaceRange)

        // Set cursor position based on template with bounds checking
        let newCursorPosition = replaceRange.location + template.cursorOffset
        let finalLength = textStorage.length
        let safeCursorPosition = min(newCursorPosition, finalLength)
        let safeCursorLength = min(template.cursorLength, max(0, finalLength - safeCursorPosition))

        let newRange = NSRange(location: safeCursorPosition, length: safeCursorLength)
        setSelectedRange(newRange)

        // Trigger syntax highlighting for the new content
        fillHighlightLinks()

        return true
    }

    // MARK: - Text Replacement Helper
    private func replaceText(_ text: String, in range: NSRange) {
        guard let textStorage = textStorage else { return }

        // Preserve text attributes when replacing
        let attributes = typingAttributes
        let attributedText = NSAttributedString(string: text, attributes: attributes)

        textStorage.replaceCharacters(in: range, with: attributedText)

        // Trigger layout update and change notification
        layoutManager?.ensureLayout(for: textContainer!)
        didChangeText()
    }
}
