import PhotosUI
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
        do {
            let markdownPath = try MobileImageWriter.write(data: data, ext: ext, into: noteFolderURL)
            let caret = selectedRange.location
            let needsLeadingNewline: Bool
            if caret > 0, caret <= (text as NSString).length {
                let previous = (text as NSString).substring(with: NSRange(location: caret - 1, length: 1))
                needsLeadingNewline = previous != "\n"
            } else {
                needsLeadingNewline = false
            }
            insertText("\(needsLeadingNewline ? "\n" : "")![](\(markdownPath))\n")
            Haptics.success()
        } catch {
            Haptics.error()
        }
    }

    // MARK: Markdown line/selection helpers (toolbar actions)

    /// Replace an NSRange through the UITextInput API so the edit lands in
    /// the undo stack and flows through the delegate like typed text.
    private func replaceCharacters(in nsRange: NSRange, with string: String) {
        guard
            let start = position(from: beginningOfDocument, offset: nsRange.location),
            let end = position(from: start, offset: nsRange.length),
            let range = textRange(from: start, to: end)
        else { return }
        replace(range, withText: string)
    }

    private var clampedCaret: NSRange {
        let length = (text as NSString).length
        let location = min(selectedRange.location, length)
        return NSRange(location: location, length: min(selectedRange.length, length - location))
    }

    func wrapSelection(with marker: String) {
        guard let range = selectedTextRange else { return }
        let selected = text(in: range) ?? ""
        if selected.isEmpty {
            let caretStart = range.start
            replace(range, withText: marker + marker)
            if let caret = position(from: caretStart, offset: marker.count) {
                selectedTextRange = textRange(from: caret, to: caret)
            }
        } else {
            replace(range, withText: marker + selected + marker)
        }
    }

    func cycleHeadingAtCaret() {
        let ns = text as NSString
        let line = ns.paragraphRange(for: NSRange(location: clampedCaret.location, length: 0))
        let lineText = ns.substring(with: line)
        let replacement: String
        if lineText.hasPrefix("### ") {
            replacement = String(lineText.dropFirst(4))
        } else if lineText.hasPrefix("## ") || lineText.hasPrefix("# ") {
            replacement = "#" + lineText
        } else {
            replacement = "# " + lineText
        }
        replaceCharacters(in: line, with: replacement)
    }

    func toggleLinePrefix(_ prefix: String) {
        let ns = text as NSString
        let block = ns.paragraphRange(for: clampedCaret)
        let lines = ns.substring(with: block).components(separatedBy: "\n")
        let content = lines.filter { !$0.isEmpty }
        let allPrefixed = !content.isEmpty && content.allSatisfy { $0.hasPrefix(prefix) }
        let mapped = lines.map { line -> String in
            if line.isEmpty { return line }
            if allPrefixed { return String(line.dropFirst(prefix.count)) }
            if line.hasPrefix(prefix) { return line }
            return prefix + line
        }
        replaceCharacters(in: block, with: mapped.joined(separator: "\n"))
    }
}

// MARK: - Photo picker bridge

@MainActor
private final class PhotoPickerPresenter: NSObject, PHPickerViewControllerDelegate {
    /// Global-actor-isolated function types are Sendable, which lets the
    /// handler hop out of the provider's background completion queues.
    typealias PickedImageHandler = @MainActor (Data, String) -> Void

    private var completion: PickedImageHandler?

    func present(completion: @escaping PickedImageHandler) {
        guard let presenter = UIApplication.shared.topMostViewController else { return }
        self.completion = completion
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else {
            completion = nil
            return
        }
        let done = completion
        completion = nil

        var candidates: [(String, String)] = [
            (UTType.png.identifier, "png"),
            (UTType.jpeg.identifier, "jpg"),
            (UTType.gif.identifier, "gif"),
        ]
        if let heic = UTType("public.heic") {
            candidates.append((heic.identifier, "heic"))
        }
        for (identifier, ext) in candidates where provider.hasItemConformingToTypeIdentifier(identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in done?(data, ext) }
            }
            return
        }
        // Unknown source type: fall back to a UIImage round-trip.
        guard provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { object, _ in
            guard let image = object as? UIImage,
                let data = image.jpegData(compressionQuality: 0.92)
            else { return }
            Task { @MainActor in done?(data, "jpg") }
        }
    }
}

// MARK: - SwiftUI wrapper

/// UITextView-backed markdown editor: plain markdown text with lightweight
/// syntax highlighting, image paste, and a markdown accessory toolbar.
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
        textView.inputAccessoryView = context.coordinator.makeToolbar(for: textView)
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
        if context.coordinator.appliedFont != bodyFont {
            context.coordinator.install(text: text, font: bodyFont, in: textView)
        } else if textView.text != text {
            context.coordinator.install(text: text, font: bodyFont, in: textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownEditorView
        private(set) var appliedFont: UIFont?
        private var theme: MarkdownEditorTheme?
        private var pendingEditRange: NSRange?
        private weak var toolbarTarget: MarkdownUITextView?
        private let photoPicker = PhotoPickerPresenter()

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
            parent.text = textView.text
            // Never touch attributes while an IME composition (Chinese,
            // Japanese, ...) is in flight — mutating textStorage ends the
            // marked-text session and breaks the input method.
            guard textView.markedTextRange == nil, let theme else { return }
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

        // MARK: Accessory toolbar

        func makeToolbar(for textView: MarkdownUITextView) -> UIToolbar {
            toolbarTarget = textView
            let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            toolbar.tintColor = MobileTheme.inkUIColor

            func item(_ systemImage: String, _ label: String, _ action: Selector) -> UIBarButtonItem {
                let item = UIBarButtonItem(
                    image: UIImage(systemName: systemImage), style: .plain, target: self, action: action)
                item.accessibilityLabel = label
                return item
            }

            toolbar.items = [
                item("number", String(localized: "Heading"), #selector(tapHeading)),
                .flexibleSpace(),
                item("bold", String(localized: "Bold"), #selector(tapBold)),
                .flexibleSpace(),
                item("list.bullet", String(localized: "List"), #selector(tapList)),
                .flexibleSpace(),
                item("checklist", String(localized: "Checklist"), #selector(tapChecklist)),
                .flexibleSpace(),
                item("photo", String(localized: "Insert Photo"), #selector(tapPhoto)),
            ]
            return toolbar
        }

        @objc private func tapHeading() {
            Haptics.tap()
            toolbarTarget?.cycleHeadingAtCaret()
        }

        @objc private func tapBold() {
            Haptics.tap()
            toolbarTarget?.wrapSelection(with: "**")
        }

        @objc private func tapList() {
            Haptics.tap()
            toolbarTarget?.toggleLinePrefix("- ")
        }

        @objc private func tapChecklist() {
            Haptics.tap()
            toolbarTarget?.toggleLinePrefix("- [ ] ")
        }

        @objc private func tapPhoto() {
            Haptics.tap()
            photoPicker.present { [weak self] data, ext in
                self?.toolbarTarget?.insertImage(data: data, ext: ext)
            }
        }
    }
}
