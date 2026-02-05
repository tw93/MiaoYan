import AVKit
import Cocoa
import Foundation

class NoteAttachment {
    public var title: String
    public var invalidateRange: NSRange?

    private var path: String
    public var url: URL
    private var cacheDir: URL?

    public var note: Note?
    public var shouldWriteCache = false
    public var imageCache: URL?

    init(title: String, path: String, url: URL, cache: URL?, invalidateRange: NSRange? = nil, note: Note? = nil) {
        self.title = title
        self.url = url
        self.path = path
        cacheDir = cache
        self.invalidateRange = invalidateRange
        self.note = note

        if url.isRemote() {
            let imageName = url.removingFragment().absoluteString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)

            if let directory = cache,
                let imageName = imageName
            {
                imageCache = directory.appendingPathComponent(imageName)
            }
        }
    }

    weak var weakTimer: Timer?

    @MainActor
    public func getAttributedString(lazy: Bool = true) -> NSMutableAttributedString? {
        let imageKey = NSAttributedString.Key(rawValue: AppIdentifier.imageURLKey)
        let pathKey = NSAttributedString.Key(rawValue: AppIdentifier.imagePathKey)
        let titleKey = NSAttributedString.Key(rawValue: AppIdentifier.imageTitleKey)

        if let dst = imageCache {
            if FileManager.default.fileExists(atPath: dst.path) {
                url = dst
            } else {
                shouldWriteCache = true
            }
        }

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let attachment = load(lazy: lazy) else { return nil }

        let attributedString = NSAttributedString(attachment: attachment)
        let mutableAttributedString = NSMutableAttributedString(attributedString: attributedString)
        let paragraphStyle = NSTextStorage.getParagraphStyle()

        let attributes =
            [
                titleKey: title,
                pathKey: path,
                imageKey: url,
                .link: url,
                .attachment: attachment,
                .paragraphStyle: paragraphStyle,
            ] as [NSAttributedString.Key: Any]

        mutableAttributedString.addAttributes(attributes, range: NSRange(0..<1))

        return mutableAttributedString
    }

    @MainActor public func cache(data: Data) {
        guard shouldWriteCache, let url = imageCache else { return }

        do {
            var isDirectory = ObjCBool(true)

            if let cacheDir = cacheDir,
                !FileManager.default.fileExists(atPath: cacheDir.path, isDirectory: &isDirectory) || !isDirectory.boolValue
            {
                try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: false, attributes: nil)
            }

            try data.write(to: url, options: .atomic)
        } catch {
            AppDelegate.trackError(error, context: "NoteAttachment.cache")
        }
    }

    public func getSize(url: URL) -> CGSize {
        var width = 0
        var height = 0
        var orientation = 0

        if url.isVideo {
            guard let track = AVURLAsset(url: url).tracks(withMediaType: AVMediaType.video).first else {
                return CGSize(width: width, height: height)
            }

            let size = track.naturalSize.applying(track.preferredTransform)
            return CGSize(width: abs(size.width), height: abs(size.height))
        }

        let url = NSURL(fileURLWithPath: url.path)
        if let imageSource = CGImageSourceCreateWithURL(url, nil) {
            let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as Dictionary?
            width = imageProperties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            height = imageProperties?[kCGImagePropertyPixelHeight] as? Int ?? 0
            orientation = imageProperties?[kCGImagePropertyOrientation] as? Int ?? 0

            if case 5...8 = orientation {
                height = imageProperties?[kCGImagePropertyPixelWidth] as? Int ?? 0
                width = imageProperties?[kCGImagePropertyPixelHeight] as? Int ?? 0
            }
        }

        return CGSize(width: width, height: height)
    }

    public static func getCacheUrl(from url: URL, prefix: String = "Preview") -> URL? {
        var temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        temporary.appendPathComponent(prefix)

        if let filePath = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
            return temporary.appendingPathComponent(filePath)
        }

        return nil
    }

    public static func savePreviewImage(url: URL, image: Image, prefix: String = "Preview") {
        var temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        temporary.appendPathComponent(prefix)

        if !FileManager.default.fileExists(atPath: temporary.path) {
            try? FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: nil)
        }

        if let url = getCacheUrl(from: url, prefix: prefix) {
            if let data = image.jpgData {
                try? data.write(to: url)
            }
        }
    }
}
