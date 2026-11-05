import AVKit
import Cocoa

extension NoteAttachment {
    @MainActor
    func load(lazy: Bool = true) -> NSTextAttachment? {
        let attachment = NSTextAttachment()

        if url.isImage {
            // If getSize(url:) reads UI state elsewhere, mark it @MainActor as well
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

    // Read UserDefaultsManagement.imagesWidth from the main actor
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
