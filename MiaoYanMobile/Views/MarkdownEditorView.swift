import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Attachment writing

enum MobileImageWriter {
    /// Attachments follow the macOS convention: an `i/` folder next to the
    /// note, referenced from markdown as `/i/<name>`, so both apps resolve
    /// the same file after sync.
    static func write(data: Data, ext: String, into noteFolder: URL) throws -> String {
        let directory = noteFolder.appendingPathComponent("i", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var name = UUID().uuidString.lowercased() + "." + ext
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            name = UUID().uuidString.lowercased() + "." + ext
        }
        let destination = directory.appendingPathComponent(name)

        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: destination, options: .forReplacing, error: &coordinationError
        ) { url in
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        return "/i/\(name)"
    }
}

// MARK: - UITextView subclass

final class MarkdownUITextView: UITextView {
    var noteFolderURL: URL?

    /// Comfortable maximum line width. Mirrors the reader CSS's
    /// `--reader-width` cap: without it, iPad (and landscape) editing runs
    /// 200+ characters per line across the full detail column.
    private static let maxTextWidth: CGFloat = 700
    private static let minHorizontalInset: CGFloat = MobileTheme.pagePadding - 5

    override func layoutSubviews() {
        super.layoutSubviews()
        let horizontal = max(Self.minHorizontalInset, (bounds.width - Self.maxTextWidth) / 2)
        if abs(textContainerInset.left - horizontal) > 0.5 {
            textContainerInset.left = horizontal
            textContainerInset.right = horizontal
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), UIPasteboard.general.hasImages {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        // Text wins when both are present: copying from a web page often
        // carries a rendered snapshot alongside the text, and the user
        // almost always means the text.
        if !pasteboard.hasStrings, pasteboard.hasImages,
            let (data, ext) = Self.imageData(from: pasteboard)
        {
            insertImage(data: data, ext: ext)
            return
        }
        super.paste(sender)
    }

    private static func imageData(from pasteboard: UIPasteboard) -> (Data, String)? {
        if let data = pasteboard.data(forPasteboardType: UTType.png.identifier) { return (data, "png") }
        if let data = pasteboard.data(forPasteboardType: UTType.jpeg.identifier) { return (data, "jpg") }
        if let data = pasteboard.data(forPasteboardType: UTType.gif.identifier) { return (data, "gif") }
        if let image = pasteboard.image, let data = image.jpegData(compressionQuality: 0.92) {
            return (data, "jpg")
        }
        return nil
    }

    func insertImage(data: Data, ext: String) {
        guard let noteFolderURL else { return }
        // The coordinated write can block for a provider round-trip on
        // iCloud/external folders; keep it off the main thread like every
        // other write path, then insert the markdown once the file exists.
        Task { [weak self] in
            do {
                let markdownPath = try await Task.detached(priority: .userInitiated) {
                    try MobileImageWriter.write(data: data, ext: ext, into: noteFolderURL)
                }.value
                guard let self else { return }
                let caret = self.selectedRange.location
                let needsLeadingNewline: Bool
                if caret > 0, caret <= (self.text as NSString).length {
                    let previous = (self.text as NSString).substring(with: NSRange(location: caret - 1, length: 1))
                    needsLeadingNewline = previous != "\n"
                } else {
                    needsLeadingNewline = false
                }
                self.insertText("\(needsLeadingNewline ? "\n" : "")![](\(markdownPath))\n")
                Haptics.success()
            } catch {
                Haptics.error()
            }
        }
    }

}

// MARK: - SwiftUI wrapper

/// UITextView-backed markdown editor: plain markdown text with lightweight
/// syntax highlighting and image paste.
/// SwiftUI's TextEditor can neither disable the system push-out line-break
/// strategy (premature CJK wraps) nor intercept paste, hence UIKit.
struct MarkdownEditorView: UIViewRepresentable {
    @Binding var text: String
    let bodyFont: UIFont
    let noteFolderURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MarkdownUITextView {
        let textView = MarkdownUITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(
            top: 14, left: MobileTheme.pagePadding - 5, bottom: 60, right: MobileTheme.pagePadding - 5)
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        // This is markdown source: smart quotes/dashes would corrupt syntax
        // (`--` becoming an en dash breaks fences and frontmatter).
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.noteFolderURL = noteFolderURL
        context.coordinator.install(text: text, font: bodyFont, in: textView)
        // Ask for keyboard focus only after the reader→editor crossfade
        // settles, so the transition and IME spin-up don't share a frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak textView] in
            textView?.becomeFirstResponder()
        }
        return textView
    }

    func updateUIView(_ textView: MarkdownUITextView, context: Context) {
        context.coordinator.parent = self
        textView.noteFolderURL = noteFolderURL
        // Never rebuild the buffer while an IME composition (Chinese,
        // Japanese, ...) is in flight: replacing attributedText ends the
        // marked-text session and silently discards what the user typed.
        guard textView.markedTextRange == nil else { return }
        if context.coordinator.appliedFont != bodyFont || textView.text != text {
            context.coordinator.install(text: text, font: bodyFont, in: textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownEditorView
        private(set) var appliedFont: UIFont?
        private var theme: MarkdownEditorTheme?
        private var pendingEditRange: NSRange?

        init(_ parent: MarkdownEditorView) {
            self.parent = parent
        }

        /// (Re)apply the full attributed content: base attributes + one
        /// whole-document highlight pass. Used on first install, external
        /// content replacement, and font changes.
        func install(text: String, font: UIFont, in textView: MarkdownUITextView) {
            let theme = MarkdownEditorTheme(bodyFont: font)
            self.theme = theme
            appliedFont = font

            let selected = textView.selectedRange
            let attributed = NSMutableAttributedString(string: text, attributes: theme.baseAttributes)
            MarkdownHighlighter.highlight(
                attributed, in: NSRange(location: 0, length: attributed.length), theme: theme)
            MarkdownHighlighter.highlightCodeFences(attributed, theme: theme)
            textView.attributedText = attributed
            textView.typingAttributes = theme.baseAttributes

            let length = (text as NSString).length
            let location = min(selected.location, length)
            textView.selectedRange = NSRange(location: location, length: 0)
        }

        // MARK: UITextViewDelegate

        func textView(
            _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
        ) -> Bool {
            // Remember where the edit lands so the highlight pass can cover
            // exactly the affected paragraphs (multi-paragraph pastes too).
            pendingEditRange = NSRange(location: range.location, length: (text as NSString).length)
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let textView = textView as? MarkdownUITextView else { return }
            // While an IME composition (Chinese, Japanese, ...) is in flight,
            // neither publish the half-composed text to the binding (autosave
            // would persist raw pinyin) nor touch attributes (mutating
            // textStorage ends the marked-text session and breaks the input
            // method). Committing the composition fires didChange again with
            // markedTextRange nil, so the binding catches up then.
            guard textView.markedTextRange == nil else { return }
            parent.text = textView.text
            guard let theme else { return }
            rehighlight(textView, theme: theme)
        }

        private func rehighlight(_ textView: MarkdownUITextView, theme: MarkdownEditorTheme) {
            let storage = textView.textStorage
            let ns = storage.string as NSString

            var editRange = pendingEditRange ?? textView.selectedRange
            pendingEditRange = nil
            if editRange.location > ns.length { editRange.location = ns.length }
            if NSMaxRange(editRange) > ns.length { editRange.length = ns.length - editRange.location }

            let paragraphs = ns.paragraphRange(for: editRange)
            storage.beginEditing()
            MarkdownHighlighter.highlight(storage, in: paragraphs, theme: theme)
            storage.endEditing()

            // Fences span paragraphs; a paragraph-scoped pass cannot see
            // them, so re-sweep the whole document — but only when fences
            // exist at all (single regex pass, cheap for typical notes).
            if ns.contains("```") {
                storage.beginEditing()
                MarkdownHighlighter.highlightCodeFences(storage, theme: theme)
                storage.endEditing()
            }
            textView.typingAttributes = theme.baseAttributes
        }
    }
}
