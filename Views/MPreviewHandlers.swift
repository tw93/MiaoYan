import Cocoa
import MiaoYanCore
import WebKit

/// The TOC badge reached the screen, so it is not offered again.
class HandlerTOCTip: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        UserDefaultsManagement.hasShownTOCTip = true
    }
}
/// A remote image the page measured once it loaded (`data-measure`), kept so
/// the next render reserves its box (`RemoteImageSizes`).
class HandlerImageSize: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any], let url = body["src"] as? String,
            let width = (body["width"] as? NSNumber)?.intValue, let height = (body["height"] as? NSNumber)?.intValue
        else { return }
        RemoteImageSizes.shared.record(url: url, width: width, height: height)
    }
}
/// A remote image the page has no size for yet asks for one here; the size
/// read from the file's header goes back to the page, which gives the image's
/// box its ratio while the file is still downloading (`RemoteImageProbe`).
class HandlerImageProbe: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let src = message.body as? String, !src.isEmpty, src.count < 4096 else { return }
        Task { @MainActor [weak webView = message.webView] in
            guard let size = await RemoteImageProbe.shared.size(of: src), let webView else { return }
            let script = "window.MiaoYanCommon && MiaoYanCommon.applyImageSize(\(HtmlManager.jsStringLiteral(src)), \(size.width), \(size.height));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
class HandlerCheckbox: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let position = message.body as? String else { return }
        // Toggle the note the preview shows, which can trail the list
        // selection while a render is still landing.
        let preview = message.webView as? MPreviewView
        guard let note = preview?.displayedNote ?? EditTextView.note else { return }
        note.ensureContentLoaded()
        let text = note.content.unLoadImages().string

        guard position.hasPrefix("line:"), let bodyLine = Int(position.dropFirst(5)),
            let range = HandlerCheckbox.taskMarkerRange(in: text, bodyLine: bodyLine)
        else { return }
        let marker = (text as NSString).substring(with: range)
        let toggled = marker == " " ? "x" : " "

        // An editable editor holding this note takes the edit itself, so the
        // next keystroke cannot copy the old buffer back over the toggle. In
        // preview mode the editor is read-only and would drop the insert.
        if let editor = preview?.window.flatMap(HandlerCheckbox.editor(in:)), editor.isEditable,
            editor.storageNote === note, editor.string == text
        {
            editor.insertText(toggled, replacementRange: range)
            return
        }
        let updated = NSMutableAttributedString(string: text)
        updated.replaceCharacters(in: range, with: toggled)
        note.save(content: updated)
    }

    /// The range of the space or x inside `[ ]` on the task item at
    /// `bodyLine`; the iPhone reader ticks through the same `TaskMarker`.
    nonisolated static func taskMarkerRange(in text: String, bodyLine: Int) -> NSRange? {
        TaskMarker.range(in: text, bodyLine: bodyLine)
    }

    private static func editor(in window: NSWindow) -> EditTextView? {
        var stack: [NSView] = window.contentView.map { [$0] } ?? []
        while let view = stack.popLast() {
            if let editor = view as? EditTextView { return editor }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }
}

// Used to solve the adaptation of the left border/title color change with background color in PPT mode.

class HandlerRevealBackgroundColor: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let vc = AppContext.shared.viewController else { return }
        let message = (message.body as! String).trimmingCharacters(in: .whitespacesAndNewlines)
        if message == "" {
            vc.titleLabel.backgroundColor = Theme.backgroundColor
        } else {
            vc.sidebarSplitView.setValue(NSColor(css: message), forKey: "dividerColor")
            vc.splitView.setValue(NSColor(css: message), forKey: "dividerColor")
        }
    }
}

class HandlerPreviewScroll: NSObject, WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let previewView = message.webView as? MPreviewView else {
            return
        }

        guard let dict = message.body as? [String: Any],
            let lineNum = (dict["line"] as? NSNumber)?.doubleValue
        else { return }
        Task { @MainActor in
            previewView.scrollDelegate?.previewDidScroll(line: CGFloat(lineNum))
        }
    }
}
