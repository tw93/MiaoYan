import Cocoa

typealias ImageView = NSImageView

extension NoteCellView {
    func loadImagesPreview(position: Int? = nil, urls: [URL]? = nil) {
        DispatchQueue.global(qos: .userInteractive).async {
            let current = Date().toMillis()
            self.timestamp = current
        }
    }
}
