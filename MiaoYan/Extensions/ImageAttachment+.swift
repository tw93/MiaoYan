//
//  ImageAttachment+.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 1/19/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa
import AVKit

extension NoteAttachment {
    public func load(lazy: Bool = true) -> NSTextAttachment? {
        let attachment = NSTextAttachment()

        let imageSize = getSize(url: self.url)
        var size = self.getSize(width: imageSize.width, height: imageSize.height)

        if url.isImage {
            attachment.bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            attachment.image = NSImage(size: size)
        } else {
            size = NSSize(width: 40, height: 40)

            if let image = NSImage(named: "file") {
                let cell = NSTextAttachmentCell(imageCell: image)
                attachment.bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                attachment.attachmentCell = cell
            }
        }

        return attachment
    }

    private func getEditorView() -> EditTextView? {
        if let cvc = ViewController.shared(), let view = cvc.editArea {
            return view
        }

        return nil
    }

    public func getSize(width: CGFloat, height: CGFloat) -> NSSize {
        var maxWidth = UserDefaultsManagement.imagesWidth

        if maxWidth == Float(1000) {
            maxWidth = Float(width)
        }

        let ratio: Float = Float(maxWidth) / Float(width)
        var size = NSSize(width: Int(width), height: Int(height))

        if ratio < 1 {
            size = NSSize(width: Int(maxWidth), height: Int(Float(height) * Float(ratio)))
        }

        return size
    }

    public static func getImageAndCacheData(url: URL, note: Note) -> Image? {
        var data: Data?

        let cacheDirectoryUrl = note.project.url.appendingPathComponent("/.cache/")

        if url.isRemote() || url.pathExtension.lowercased() == "png", let cacheName = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {

            let imageCacheUrl = cacheDirectoryUrl.appendingPathComponent(cacheName)

            if !FileManager.default.fileExists(atPath: imageCacheUrl.path) {
                var isDirectory = ObjCBool(true)
                if !FileManager.default.fileExists(atPath: cacheDirectoryUrl.path, isDirectory: &isDirectory) || isDirectory.boolValue == false {
                    do {
                        try FileManager.default.createDirectory(at: imageCacheUrl.deletingLastPathComponent(), withIntermediateDirectories: false, attributes: nil)
                    } catch {
                        print(error)
                    }
                }

                do {
                    data = try Data(contentsOf: url)
                } catch {
                    print(error)
                }

            } else {
                data = try? Data(contentsOf: imageCacheUrl)
            }
        } else {
            data = try? Data(contentsOf: url)
        }

        guard let imageData = data else { return nil }

        return Image(data: imageData)
    }

    public static func getImage(url: URL, size: CGSize) -> NSImage? {
        let imageData = try? Data(contentsOf: url)
        var finalImage: NSImage?

        if url.isVideo {
            let asset = AVURLAsset(url: url, options: nil)
            let imgGenerator = AVAssetImageGenerator(asset: asset)
            if let cgImage = try? imgGenerator.copyCGImage(at: CMTimeMake(value: 0, timescale: 1), actualTime: nil) {
                finalImage = NSImage(cgImage: cgImage, size: size)
            }
        } else if let imageData = imageData {
            finalImage = NSImage(data: imageData)
        }

        guard let image = finalImage else { return nil }
        var thumbImage: NSImage?
        thumbImage = finalImage

        if let cacheURL = self.getCacheUrl(from: url, prefix: "ThumbnailsBig"), FileManager.default.fileExists(atPath: cacheURL.path) {
            thumbImage = NSImage(contentsOfFile: cacheURL.path)
        } else if
            let resizedImage = image.resized(to: size) {
            thumbImage = resizedImage

            self.savePreviewImage(url: url, image: resizedImage, prefix: "ThumbnailsBig")
        }

        return thumbImage
    }
}
