import AppKit
import SwiftUI

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
    /// Called after an edit lands in the note, so a visible preview can follow.
    var onContentChange: (() -> Void)?
    /// Called before an edit is saved, so disk events from the save itself
    /// can be held off.
    var onWillSave: (() -> Void)?

    private let formatWorker = MarkdownFormatWorker()
    private var formatTask: Task<Void, Never>?
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

    /// Loads `note` unless the buffer already holds it.
    func show(_ note: Note) {
        guard textView.storageNote !== note else { return }
        textView.fill(note: note, options: .default)
        textView.updateTextContainerInset()
    }

    /// Reloads `note` into the buffer after it changed on disk, keeping the
    /// scroll position.
    func reload(_ note: Note) {
        let top = scrollView.contentView.bounds.origin.y
        textView.fill(note: note, options: FillOptions(highlight: false, saveTyping: false, force: true, needScrollToCursor: false))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: top))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - NSTextViewDelegate

    /// ViewController.textDidChange, without the pieces that belong to the
    /// storyboard window (its line cache, its file-watcher pause).
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
        onContentChange?()
    }

    // MARK: - Format

    /// ViewController.formatText: Prettier on a background actor, applied
    /// only if the same note still owns the buffer when it returns.
    func format(in host: NSViewController) {
        if formatTask != nil {
            formatTask?.cancel()
            formatTask = nil
            host.toast(message: I18n.str("Formatting cancelled"))
            return
        }
        guard let note = EditTextView.note, textView.storageNote === note else { return }
        let content = textView.textStorage?.string ?? note.content.string
        let cursor = textView.selectedRange().location
        let top = scrollView.contentView.bounds.origin.y
        let noteURL = note.url

        formatTask = Task { [weak self, weak host] in
            guard let self else { return }
            defer { self.formatTask = nil }
            do {
                let output = try await self.formatWorker.format(content: content, cursor: cursor)
                guard !Task.isCancelled, let note = EditTextView.note, note.url == noteURL,
                    self.textView.storageNote === note
                else { return }
                self.apply(output, original: content, note: note, top: top)
                host?.toast(message: I18n.str("Automatic typesetting succeeded~"), style: .success)
            } catch is CancellationError {
            } catch {
                AppDelegate.trackError(error, context: "ShellEditorController.format")
            }
        }
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
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: top))
        scrollView.reflectScrolledClipView(scrollView.contentView)
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
        controller.show(note)
        return controller.container
    }

    func updateNSView(_ view: NSView, context: Context) {
        controller.show(note)
    }
}
