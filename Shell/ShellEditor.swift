import AppKit
import MiaoYanCore
import SwiftUI

/// The storyboard window's split-view arithmetic, kept free of views so it
/// can be tested: the pane widths of `EditorContentSplitView`, the preview
/// debounce of `EditTextView` and the line mapping of the scroll sync in
/// `ViewController+Editor`.
enum ShellSplitMath {
    static let minPaneWidth: CGFloat = 200
    static let maxPaneWidth: CGFloat = 1200
    static let preferredDefaultWidth: CGFloat = 600
    /// The preview follows typing this long after the last key.
    static let typingDelay: TimeInterval = 0.15

    /// The editor pane's width for a split `total` points wide: the saved
    /// ratio, or half (at most 600pt) the first time, kept 200pt from either
    /// edge and under 1200pt.
    static func editorWidth(total: CGFloat, savedRatio: Double) -> CGFloat {
        let total = max(total, 1)
        var width = savedRatio > 0 ? total * CGFloat(min(savedRatio, 1)) : min(total * 0.5, preferredDefaultWidth)
        width = max(minPaneWidth, min(width, min(total - minPaneWidth, maxPaneWidth)))
        return min(width, total)
    }

    /// A new line or a paste re-renders at once; single keys wait a beat.
    static func previewDelay(forReplacement replacement: String?) -> TimeInterval {
        guard let replacement else { return typingDelay }
        return replacement.contains(where: \.isNewline) || replacement.count > 1 ? 0 : typingDelay
    }

    /// The character index each line starts at.
    static func lineStarts(of text: String) -> [Int] {
        let ns = text as NSString
        var starts = [0]
        let all = NSRange(location: 0, length: ns.length)
        ns.enumerateSubstrings(in: all, options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
            let next = NSMaxRange(enclosing)
            if next < ns.length { starts.append(next) }
        }
        return starts
    }

    /// The 1-based line of the body (the numbering the preview's
    /// data-sourcepos uses, without the frontmatter) holding `index`.
    static func bodyLine(atCharacter index: Int, lineStarts starts: [Int], frontmatterLines: Int) -> Int {
        guard !starts.isEmpty else { return 1 }
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= index { low = mid } else { high = mid - 1 }
        }
        return max(low + 1 - frontmatterLines, 1)
    }

    /// The 0-based buffer line a preview position (1-based body line plus a
    /// fraction) falls on, and how far into that line.
    static func bufferLine(forPreviewLine line: CGFloat, frontmatterLines: Int) -> (line: Int, fraction: CGFloat) {
        let whole = Int(line)
        return (whole - 1 + frontmatterLines, line - CGFloat(whole))
    }
}

/// Owns the one `EditTextView` the shell uses and does for it what
/// `ViewController` does for the storyboard editor: configures it, fills it
/// with the open note and persists every edit. The editor survives mode
/// switches, so its undo history and scroll position do too.
@available(macOS 14, *)
@MainActor
final class ShellEditorController: NSObject, NSTextViewDelegate {
    /// Holds the scroll view and, when open, the editor's find bar.
    let container = NSView()
    let scrollView: ShellEditorScrollView
    let textView: EditTextView
    /// Called after an edit lands in the note.
    var onContentChange: (() -> Void)?
    /// Called before an edit is saved, so disk events from the save itself
    /// can be held off.
    var onWillSave: (() -> Void)?
    /// Called when Format starts and ends, for the button's busy state.
    var onFormattingChange: ((Bool) -> Void)?

    private let formatWorker = MarkdownFormatWorker()
    private var formatTask: Task<Void, Never>?
    private var formatRequestID = 0
    /// The text Format or Clean Typography left, so the Command-Z that
    /// undoes it keeps the cursor where it is, as in the storyboard window.
    private var formatContent = ""

    override init() {
        scrollView = ShellEditorScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        textView = EditTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        textView.isShellHosted = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.focusRingType = .none
        textView.allowsUndo = true
        textView.usesFontPanel = true
        textView.smartInsertDeleteEnabled = true
        textView.drawsBackground = true
        textView.backgroundColor = ShellPalette.background
        textView.insertionPointColor = .textColor
        textView.configureOnLoad()

        // ViewController.configureEditor
        textView.usesFindBar = false
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textStorage?.delegate = textView.textStorage
        textView.linkTextAttributes = [.foregroundColor: Theme.highlightColor]

        super.init()
        textView.delegate = self
        scrollView.documentView = textView
        scrollView.editor = textView
        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.width, .height]
        container.addSubview(scrollView)
    }

    /// The list's search, whose keywords an opened note highlights.
    var searchQuery: (() -> String)? {
        get { textView.shellSearchText }
        set { textView.shellSearchText = newValue }
    }

    /// The editor comes on screen with `note`. Loads it unless the buffer
    /// already holds it, and then takes any text written while the editor
    /// was away: a task ticked in the preview is saved to the note alone,
    /// since the hidden editor is out of the window where the checkbox
    /// handler looks for it, and the next keystroke would otherwise save the
    /// old buffer back over the tick.
    func show(_ note: Note) {
        if textView.storageNote === note {
            refillIfStale(note)
        } else {
            update(note)
        }
        // Once the pane is laid out, for what a mode change left to do
        // (selection, scroll, focus).
        DispatchQueue.main.async { [weak self] in self?.onShow?() }
    }

    /// Called after the editor comes on screen.
    var onShow: (() -> Void)?

    /// The editor is already on screen and the open note may have changed.
    func update(_ note: Note) {
        guard textView.storageNote !== note else { return }
        // NotesTableView: switching notes closes the editor's find bar.
        if textView.isSearchBarVisible { textView.hideSearchBar(restoreFocus: false) }
        // The storyboard list's fill: keywords of a search highlighted, the
        // scroll left alone rather than moved to the saved cursor.
        textView.fill(note: note, options: .silent)
        textView.updateTextContainerInset()
        // Another note starts at its top. The scroll offset of a longer note
        // read before left a short one scrolled past its end, a blank pane.
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        invalidateLineStarts()
    }

    private func refillIfStale(_ note: Note) {
        guard note.isContentLoaded, !note.loadFailed, let storage = textView.textStorage else { return }
        let buffer =
            storage.containsAttachments
            ? NSMutableAttributedString(attributedString: storage).unLoadImages().unLoadCheckboxes().string : storage.string
        guard buffer != note.content.string else { return }
        let selection = textView.selectedRange()
        reload(note)
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
    }

    /// Reloads `note` into the buffer after it changed on disk, keeping the
    /// scroll position.
    func reload(_ note: Note) {
        let top = scrollView.contentView.bounds.origin.y
        textView.fill(note: note, options: FillOptions(highlight: false, saveTyping: false, force: true, needScrollToCursor: false))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: top))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        invalidateLineStarts()
    }

    // MARK: - Scroll position

    /// How far down the editor is scrolled, 0 to 1.
    var scrollRatio: CGFloat {
        guard let document = scrollView.documentView else { return 0 }
        let range = document.bounds.height - scrollView.contentSize.height
        let top = scrollView.contentView.bounds.origin.y
        return range > 0 && top > 0 ? top / range : 0
    }

    func setScrollRatio(_ ratio: CGFloat) {
        scrollView.layoutSubtreeIfNeeded()
        if let container = textView.textContainer { textView.layoutManager?.ensureLayout(for: container) }
        guard ratio > 0, let document = scrollView.documentView else { return }
        let range = max(document.bounds.height - scrollView.contentSize.height, 0)
        guard range > 0 else { return }
        document.scroll(NSPoint(x: 0, y: range * min(ratio, 1)))
    }

    /// The body line at the top of the editor, for the preview to scroll to.
    func topBodyLine() -> CGFloat {
        guard let layout = textView.layoutManager, let container = textView.textContainer, let storage = textView.textStorage
        else { return 1 }
        let y = max(scrollView.contentView.bounds.origin.y - textView.textContainerOrigin.y, 0)
        let index = layout.characterIndex(for: NSPoint(x: 8, y: y), in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        let starts = lineStarts()
        return CGFloat(
            ShellSplitMath.bodyLine(atCharacter: min(index, storage.length), lineStarts: starts, frontmatterLines: frontmatterLines))
    }

    private var lineStartsCache: [Int]?
    private var lineStartsLength = -1
    private var frontmatterLines = 0

    private func lineStarts() -> [Int] {
        let text = textView.string
        let length = (text as NSString).length
        if let cached = lineStartsCache, lineStartsLength == length { return cached }
        let starts = ShellSplitMath.lineStarts(of: text)
        lineStartsCache = starts
        lineStartsLength = length
        frontmatterLines = Frontmatter.lineCount(of: text)
        return starts
    }

    private func invalidateLineStarts() {
        lineStartsCache = nil
        lineStartsLength = -1
    }

    private func lineRect(_ line: Int) -> NSRect {
        guard let layout = textView.layoutManager, let container = textView.textContainer, let storage = textView.textStorage
        else { return .zero }
        let starts = lineStarts()
        guard !starts.isEmpty else { return .zero }
        let location = min(starts[max(0, min(line, starts.count - 1))], storage.length)
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: location, length: 0), actualCharacterRange: nil)
        let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        return rect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
    }

    // MARK: - Split view

    /// The preview beside the editor in split mode. While set, the two
    /// scroll together and the preview follows typing.
    private(set) weak var splitPreview: MPreviewView?
    private var clipObserver: NSObjectProtocol?
    /// Held while one side scrolls the other, so the echo does not bounce back.
    private var syncSuppression = 0
    private var lastSyncedLine: CGFloat = -1
    private var previewDelay = ShellSplitMath.typingDelay
    private var previewTimer: Timer?

    func attachSplitPreview(_ preview: MPreviewView?) {
        guard preview !== splitPreview else { return }
        splitPreview?.scrollDelegate = nil
        if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
        clipObserver = nil
        previewTimer?.invalidate()
        previewTimer = nil
        syncSuppression = 0
        lastSyncedLine = -1
        splitPreview = preview
        guard let preview else { return }
        preview.scrollDelegate = self
        // The editor's scroller is the one indicator, as in the storyboard
        // window's split; the sync keeps the two aligned.
        preview.setSplitChrome(true)
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        clipObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.editorDidScroll() }
        }
        preview.runWhenPreviewReady { [weak self] in self?.syncPreviewToEditor(force: true) }
    }

    private func editorDidScroll() {
        guard syncSuppression == 0, let preview = splitPreview, !preview.isUpdatingContent else { return }
        syncPreviewToEditor(force: false)
    }

    private func syncPreviewToEditor(force: Bool) {
        guard let preview = splitPreview else { return }
        let line = topBodyLine()
        guard force || abs(line - lastSyncedLine) >= 0.25 else { return }
        lastSyncedLine = line
        syncSuppression += 1
        preview.scrollToLine(line)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.syncSuppression = max(0, self.syncSuppression - 1)
        }
    }

    /// Re-renders the split preview after `delay`, unless an input method is
    /// still composing when it fires; its commit re-schedules.
    private func schedulePreviewUpdate() {
        guard splitPreview != nil else { return }
        previewTimer?.invalidate()
        // A change made by code, not a key, renders at once.
        let delay = textView.window?.currentEvent == nil ? 0 : previewDelay
        previewDelay = ShellSplitMath.typingDelay
        previewTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.textView.hasMarkedText() else { return }
                self.refreshSplitPreview()
            }
        }
    }

    private func refreshSplitPreview() {
        guard let preview = splitPreview, let note = textView.storageNote, note === EditTextView.note else { return }
        preview.updateContent(note: note)
    }

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        previewDelay = ShellSplitMath.previewDelay(forReplacement: replacementString)
        return true
    }

    /// ViewController.textDidChange, without the pieces that belong to the
    /// storyboard window (its file-watcher pause).
    func textDidChange(_ notification: Notification) {
        guard let note = EditTextView.note else { return }
        // The buffer must belong to the note being saved (#543).
        guard textView.storageNote === note else {
            let mismatch = NSError(
                domain: "com.tw93.miaoyan.race",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "textStorage owner drift in shell textDidChange"])
            AppDelegate.trackError(mismatch, context: "ShellEditorController.textDidChange.ownerGuard")
            return
        }
        onWillSave?()
        textView.saveTextStorageContent(to: note)
        note.save(content: note.content)
        invalidateLineStarts()
        schedulePreviewUpdate()
        onContentChange?()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        EditTextView.note?.undoManager
    }

    // MARK: - Clean typography

    /// ViewController.cleanTypography: CJK spacing and punctuation fixes over
    /// the whole buffer, written through the text view so one undo reverts it.
    func cleanTypography(in host: NSViewController) {
        guard let note = EditTextView.note, textView.storageNote === note else { return }
        let content = textView.textStorage?.string ?? note.content.string
        let cleaned = TypographyCleaner.clean(content)
        guard cleaned != content else {
            host.toast(message: I18n.str("Typography is already clean~"))
            return
        }
        let cursor = textView.selectedRange().location
        let top = scrollView.contentView.bounds.origin.y
        EditTextView.shouldForceRescan = true
        textView.breakUndoCoalescing()
        textView.insertText(cleaned, replacementRange: NSRange(location: 0, length: (textView.string as NSString).length))
        textView.saveTextStorageContent(to: note)
        note.save()
        formatContent = cleaned
        textView.setSelectedRange(NSRange(location: min(cursor, (cleaned as NSString).length), length: 0))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: top))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        host.toast(message: I18n.str("Typography cleaned up~"), style: .success)
        refreshSplitPreview()
        onContentChange?()
    }

    // MARK: - Format

    /// ViewController.formatText: Prettier on a background actor, applied
    /// only if the same note still owns the buffer when it returns. A second
    /// click while it runs cancels it.
    func format(in host: NSViewController) {
        if let running = formatTask {
            running.cancel()
            formatTask = nil
            formatRequestID &+= 1
            onFormattingChange?(false)
            host.toast(message: I18n.str("Formatting cancelled"))
            return
        }
        guard let note = EditTextView.note, textView.storageNote === note else { return }
        let content = textView.textStorage?.string ?? note.content.string
        let cursor = textView.selectedRange().location
        let top = scrollView.contentView.bounds.origin.y
        let noteURL = note.url
        formatRequestID &+= 1
        let requestID = formatRequestID

        formatTask = Task { [weak self, weak host] in
            guard let self else { return }
            defer {
                if self.formatRequestID == requestID {
                    self.formatTask = nil
                    self.onFormattingChange?(false)
                }
            }
            do {
                let output = try await self.formatWorker.format(content: content, cursor: cursor)
                guard !Task.isCancelled, self.formatRequestID == requestID, let note = EditTextView.note, note.url == noteURL,
                    self.textView.storageNote === note
                else { return }
                self.apply(output, original: content, note: note, top: top)
                host?.toast(message: I18n.str("Automatic typesetting succeeded~"), style: .success)
            } catch is CancellationError {
            } catch {
                AppDelegate.trackError(error, context: "ShellEditorController.format")
                guard self.formatRequestID == requestID else { return }
                host?.toast(message: I18n.str("Formatting failed, please try again"), style: .failure)
            }
        }
        onFormattingChange?(true)
    }

    private func apply(_ output: MarkdownFormatOutput, original: String, note: Note, top: CGFloat) {
        let restored = HtmlManager.restoreHTMLTags(in: output.formattedString, with: output.placeholders)
        var newContent = restored
        if original.components(separatedBy: .newlines).count > 1 && !restored.contains("\n") {
            newContent = original
        } else if original.last != "\n" && restored.last == "\n" {
            newContent = restored.removeLastNewLine()
        }

        if let storage = textView.textStorage {
            storage.beginEditing()
            storage.replaceCharacters(in: NSRange(0..<storage.length), with: newContent)
            NotesTextProcessor.checkPerformanceLevel(attributedString: storage, note: note)
            if NotesTextProcessor.shouldUseSimplifiedHighlighting {
                NotesTextProcessor.highlightBasicMarkdown(attributedString: storage, note: note)
            } else {
                NotesTextProcessor.highlightMarkdown(attributedString: storage, note: note)
                NotesTextProcessor.highlightFencedAndIndentCodeBlocks(attributedString: storage)
            }
            storage.updateParagraphStyle()
            NotesTextProcessor(storage: storage, range: NSRange(location: 0, length: storage.length)).highlightLinks()
            storage.applyEditorLetterSpacing()
            storage.endEditing()
        }

        let cursor = HtmlManager.adjustCursorAfterRestore(
            originalOffset: output.cursorOffset, protected: output.protectedContent, restored: newContent)
        textView.setSelectedRange(NSRange(location: min(cursor, newContent.utf16.count), length: 0))
        note.save(attributed: textView.attributedString())
        formatContent = newContent
        invalidateLineStarts()
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: top))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        refreshSplitPreview()
        onContentChange?()
    }

    /// Called as Command-Z reaches the editor: when it undoes the last
    /// Format, put the cursor back where it was once the undo has run.
    func keepCursorThroughFormatUndo() {
        guard !formatContent.isEmpty, let note = EditTextView.note, textView.storageNote === note,
            note.content.string == formatContent
        else { return }
        formatContent = ""
        let cursor = textView.selectedRange().location
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let length = (self.textView.string as NSString).length
            self.textView.setSelectedRange(NSRange(location: min(cursor, length), length: 0))
        }
    }
}

@available(macOS 14, *)
extension ShellEditorController: MPreviewScrollDelegate {
    /// The split preview scrolled: bring the editor to the same source line.
    func previewDidScroll(line: CGFloat) {
        guard syncSuppression == 0, let preview = splitPreview, !preview.isUpdatingContent else { return }
        syncSuppression += 1
        defer {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.syncSuppression = max(0, self.syncSuppression - 1)
            }
        }
        _ = lineStarts()
        let target = ShellSplitMath.bufferLine(forPreviewLine: line, frontmatterLines: frontmatterLines)
        let rect = lineRect(target.line)
        guard rect != .zero, let document = scrollView.documentView else { return }
        let maxOffset = max(document.bounds.height - scrollView.contentSize.height, 0)
        let y = max(0, min(rect.minY + target.fraction * rect.height, maxOffset))
        guard abs(y - scrollView.contentView.bounds.origin.y) > 0.5 else { return }
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

/// Recomputes the editor's side margins whenever the pane changes width, as
/// the storyboard layout does on every resize.
@available(macOS 14, *)
final class ShellEditorScrollView: NSScrollView {
    weak var editor: EditTextView?

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged {
            editor?.updateTextContainerInset()
        }
    }
}

@available(macOS 14, *)
struct ShellEditorView: NSViewRepresentable {
    let controller: ShellEditorController
    let note: Note

    func makeNSView(context: Context) -> NSView {
        // SwiftUI sizes the container here; the split pane's resizing mask
        // stays behind with that pane.
        controller.container.autoresizingMask = []
        controller.show(note)
        return controller.container
    }

    func updateNSView(_ view: NSView, context: Context) {
        controller.update(note)
    }
}

/// Split mode's two panes: the editor and the preview side by side with a
/// divider that can be dragged, its position kept as a ratio in the same
/// preference the storyboard window's `EditorContentSplitView` uses.
@available(macOS 14, *)
struct ShellEditorSplit<Preview: View>: NSViewRepresentable {
    let controller: ShellEditorController
    let note: Note
    let preview: Preview

    @MainActor
    final class Coordinator: NSObject, NSSplitViewDelegate {
        var ratio = UserDefaultsManagement.editorContentSplitPosition

        func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
            guard splitView.subviews.count == 2 else { return }
            let thickness = splitView.dividerThickness
            let total = max(splitView.bounds.width - thickness, 0)
            let left = ShellSplitMath.editorWidth(total: total, savedRatio: ratio)
            let height = splitView.bounds.height
            splitView.subviews[0].frame = NSRect(x: 0, y: 0, width: left, height: height)
            splitView.subviews[1].frame = NSRect(x: left + thickness, y: 0, width: max(total - left, 0), height: height)
            Self.fitEditor(in: splitView)
        }

        /// The editor container arrives from the edit-only view still sized to
        /// the whole detail column; left alone it ran under the preview, cut
        /// its lines off at the divider and took the preview's scroll events.
        static func fitEditor(in splitView: NSSplitView) {
            guard let pane = splitView.subviews.first else { return }
            for view in pane.subviews where view.frame != pane.bounds {
                view.frame = pane.bounds
            }
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
            ShellSplitMath.minPaneWidth
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
            splitView.bounds.width - ShellSplitMath.minPaneWidth
        }

        /// Only a divider drag carries a divider index; window resizes keep
        /// the ratio rather than saving whatever the clamp left.
        func splitViewDidResizeSubviews(_ notification: Notification) {
            if let splitView = notification.object as? NSSplitView { Self.fitEditor(in: splitView) }
            guard notification.userInfo?["NSSplitViewDividerIndex"] != nil,
                let splitView = notification.object as? NSSplitView, splitView.subviews.count == 2
            else { return }
            let total = max(splitView.bounds.width - splitView.dividerThickness, 1)
            ratio = Double(splitView.subviews[0].frame.width / total)
            UserDefaultsManagement.editorContentSplitPosition = ratio
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ShellSplitView {
        let split = ShellSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = context.coordinator
        let editorPane = NSView()
        controller.container.frame = editorPane.bounds
        controller.container.autoresizingMask = [.width, .height]
        editorPane.addSubview(controller.container)
        let previewPane = NSHostingView(rootView: preview)
        previewPane.sizingOptions = []
        split.addSubview(editorPane)
        split.addSubview(previewPane)
        controller.show(note)
        return split
    }

    func updateNSView(_ split: ShellSplitView, context: Context) {
        if let editorPane = split.subviews.first, controller.container.superview !== editorPane {
            editorPane.addSubview(controller.container)
        }
        controller.container.autoresizingMask = [.width, .height]
        Coordinator.fitEditor(in: split)
        (split.subviews.last as? NSHostingView<Preview>)?.rootView = preview
        controller.update(note)
    }
}
