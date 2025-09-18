import AVKit
import Cocoa

extension NoteAttachment {
    @MainActor
    func load(lazy: Bool = true) -> NSTextAttachment? {
        let attachment = NSTextAttachment()

        if url.isImage {
            // 这里的 getSize(url:) 若在别处定义且会读 UI 状态，也应是 @MainActor
            let imageSize = getSize(url: url)
            let size = getSize(width: imageSize.width, height: imageSize.height)
            attachment.bounds = CGRect(origin: .zero, size: size)
            attachment.image = NSImage(size: size)
        } else {
            let size = NSSize(width: 40, height: 40)
            attachment.bounds = CGRect(origin: .zero, size: size)

            if let image = NSImage(named: "file") {
                let cell = NSTextAttachmentCell(imageCell: image)
                attachment.attachmentCell = cell
            }
        }

        return attachment
    }

    @MainActor
    private func getEditorView() -> EditTextView? {
        ViewController.shared()?.editArea
    }

    // 读取 UserDefaultsManagement.imagesWidth → 主线程
    @MainActor
    func getSize(width: CGFloat, height: CGFloat) -> NSSize {
        let configuredMax = UserDefaultsManagement.imagesWidth
        let maxWidth = configuredMax == Float(1000) ? Float(width) : configuredMax

        let ratio = maxWidth / Float(width)
        if ratio < 1 {
            return NSSize(width: Int(maxWidth), height: Int(Float(height) * ratio))
        } else {
            return NSSize(width: Int(width), height: Int(height))
        }
    }

    // 访问 note.project（主线程隔离）→ 主线程
    @MainActor
    static func getImageAndCacheData(url: URL, note: Note) -> Image? {
        let cacheDirectoryUrl = note.project.url.appendingPathComponent("/.cache/")

        let data: Data?
        if shouldUseCache(for: url),
           let cacheName = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
            let imageCacheUrl = cacheDirectoryUrl.appendingPathComponent(cacheName)
            data = getCachedOrFetchData(imageCacheUrl: imageCacheUrl, originalUrl: url, cacheDirectoryUrl: cacheDirectoryUrl)
        } else {
            data = try? Data(contentsOf: url)
        }

        guard let imageData = data else { return nil }
        return Image(data: imageData)
    }

    private static func shouldUseCache(for url: URL) -> Bool {
        url.isRemote() || url.pathExtension.lowercased() == "png"
    }

    // 非隔离函数里调用 trackError → hop 到主线程
    private static func getCachedOrFetchData(imageCacheUrl: URL, originalUrl: URL, cacheDirectoryUrl: URL) -> Data? {
        if FileManager.default.fileExists(atPath: imageCacheUrl.path) {
            return try? Data(contentsOf: imageCacheUrl)
        }

        ensureCacheDirectoryExists(cacheDirectoryUrl: cacheDirectoryUrl)

        do {
            return try Data(contentsOf: originalUrl)
        } catch {
            Task { @MainActor in
                AppDelegate.trackError(error, context: "ImageAttachment+.loadImage")
            }
            return nil
        }
    }

    // 同上：错误打点放到主线程
    private static func ensureCacheDirectoryExists(cacheDirectoryUrl: URL) {
        var isDirectory = ObjCBool(true)
        let fileExists = FileManager.default.fileExists(atPath: cacheDirectoryUrl.path, isDirectory: &isDirectory)

        if !fileExists || !isDirectory.boolValue {
            do {
                try FileManager.default.createDirectory(
                    at: cacheDirectoryUrl,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                Task { @MainActor in
                    AppDelegate.trackError(error, context: "ImageAttachment+.loadFileWrapper")
                }
            }
        }
    }

    static func getImage(url: URL, size: CGSize) -> NSImage? {
        let finalImage: NSImage?

        if url.isVideo {
            finalImage = generateVideoThumbnail(url: url, size: size)
        } else {
            finalImage = loadImageFromFile(url: url)
        }

        guard let image = finalImage else { return nil }

        return getCachedThumbnail(for: url, size: size)
            ?? generateThumbnail(from: image, url: url, size: size)
    }

    private static func generateVideoThumbnail(url: URL, size: CGSize) -> NSImage? {
        let asset = AVURLAsset(url: url, options: nil)
        let imgGenerator = AVAssetImageGenerator(asset: asset)

        guard let cgImage = try? imgGenerator.copyCGImage(at: CMTimeMake(value: 0, timescale: 1), actualTime: nil) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: size)
    }

    private static func loadImageFromFile(url: URL) -> NSImage? {
        guard let imageData = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: imageData)
    }

    private static func getCachedThumbnail(for url: URL, size: CGSize) -> NSImage? {
        guard let cacheURL = getCacheUrl(from: url, prefix: "ThumbnailsBig"),
              FileManager.default.fileExists(atPath: cacheURL.path)
        else {
            return nil
        }
        return NSImage(contentsOfFile: cacheURL.path)
    }

    private static func generateThumbnail(from image: NSImage, url: URL, size: CGSize) -> NSImage? {
        guard let resizedImage = image.resized(to: NSSize(width: size.width, height: size.height)) else {
            return image
        }

        savePreviewImage(url: url, image: resizedImage, prefix: "ThumbnailsBig")
        return resizedImage
    }
}
