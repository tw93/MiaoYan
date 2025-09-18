import Cocoa

@MainActor
class ImagePreviewManager {
    private weak var textView: EditTextView?
    private var imagePreviewWindow: ImagePreviewWindow?
    private var hoverTimer: Timer?
    private var lastHoveredImageInfo: ImageLinkInfo?
    private var lastShowPoint: NSPoint?

    init(textView: EditTextView) {
        self.textView = textView
    }

    func handleImageLinkHover(at index: Int, mousePoint: NSPoint) {
        guard let textView = textView,
            let storage = textView.textStorage,
            let window = textView.window
        else {
            hideImagePreview()
            return
        }

        if shouldDisableImagePreview() {
            hideImagePreview()
            return
        }

        let screenPoint = window.convertPoint(toScreen: mousePoint)

        if let lastPoint = lastShowPoint,
            imagePreviewWindow?.isPointInToleranceArea(screenPoint, originalPoint: lastPoint) == true
        {
            return
        }

        let text = storage.string

        if let imageInfo = ImageLinkParser.detectImageLink(in: text, at: index) {
            if let lastInfo = lastHoveredImageInfo,
                lastInfo.src == imageInfo.src && lastInfo.range.location == imageInfo.range.location && lastInfo.range.length == imageInfo.range.length
            {
                return
            }

            lastHoveredImageInfo = imageInfo
            hoverTimer?.invalidate()

            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, !self.shouldDisableImagePreview() else { return }
                    self.showImagePreview(for: imageInfo, at: mousePoint)
                }
            }
        } else {
            if lastHoveredImageInfo != nil {
                hideImagePreview()
            }
        }
    }

    private func showImagePreview(for imageInfo: ImageLinkInfo, at mousePoint: NSPoint) {
        if imagePreviewWindow == nil {
            imagePreviewWindow = ImagePreviewWindow()
        }

        guard let textView = textView,
            let window = textView.window
        else { return }

        let screenPoint = window.convertPoint(toScreen: mousePoint)
        lastShowPoint = screenPoint
        imagePreviewWindow?.showPreview(for: imageInfo.src, at: screenPoint, isFixed: true)
    }

    func hideImagePreview() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        lastHoveredImageInfo = nil
        lastShowPoint = nil
        imagePreviewWindow?.hidePreview()
    }

    func handleMouseClick(at point: NSPoint) {
        guard let textView = textView,
            let window = textView.window
        else { return }

        let screenPoint = window.convertPoint(toScreen: point)

        if let lastPoint = lastShowPoint,
            imagePreviewWindow?.isPointInToleranceArea(screenPoint, originalPoint: lastPoint) != true
        {
            hideImagePreview()
        }
    }

    private func shouldDisableImagePreview() -> Bool {
        guard let textView = textView else { return true }

        let selection = textView.selectedRange()
        if selection.length > 0 {
            return true
        }

        if textView.window != nil, let event = NSApp.currentEvent {
            if event.type == .leftMouseDragged || event.type == .leftMouseDown {
                return true
            }
        }

        if textView.hasMarkedText() {
            return true
        }

        return false
    }
}
