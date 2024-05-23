//
//  NSImage+.swift
//  FSNotesCore macOS
//
//  Created by Oleksandr Glushchenko on 10/14/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import AppKit

public extension NSImage {
    var height: CGFloat {
        size.height
    }

    /// Returns the width of the current image.
    var width: CGFloat {
        size.width
    }

    /// Returns a png representation of the current image.
    var PNGRepresentation: Data? {
        if let tiff = tiffRepresentation, let tiffData = NSBitmapImageRep(data: tiff) {
            return tiffData.representation(using: .png, properties: [:])
        }

        return nil
    }

    var JPEGRepresentation: Data? {
        if let tiff = tiffRepresentation, let tiffData = NSBitmapImageRep(data: tiff) {
            return tiffData.representation(using: .jpeg, properties: [:])
        }
        return nil
    }

    ///  Copies the current image and resizes it to the given size.
    ///
    ///  - parameter size: The size of the new image.
    ///
    ///  - returns: The resized copy of the given image.
    func copy(size: NSSize) -> NSImage? {
        // Create a new rect with given width and height
        let frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)

        // Get the best representation for the given size.
        guard let rep = bestRepresentation(for: frame, context: nil, hints: nil) else {
            return nil
        }

        // Create an empty image with the given size.
        let img = NSImage(size: size)

        // Set the drawing context and make sure to remove the focus before returning.
        img.lockFocus()
        defer { img.unlockFocus() }

        // Draw the new image
        if rep.draw(in: frame) {
            return img
        }

        // Return nil in case something went wrong.
        return nil
    }

    ///  Copies the current image and resizes it to the size of the given NSSize, while
    ///  maintaining the aspect ratio of the original image.
    ///
    ///  - parameter size: The size of the new image.
    ///
    ///  - returns: The resized copy of the given image.
    func resizeWhileMaintainingAspectRatioToSize(size: NSSize) -> NSImage? {
        let newSize: NSSize

        let widthRatio = size.width / width
        let heightRatio = size.height / height

        if widthRatio > heightRatio {
            newSize = NSSize(width: floor(width * widthRatio), height: floor(height * widthRatio))
        } else {
            newSize = NSSize(width: floor(width * heightRatio), height: floor(height * heightRatio))
        }

        return copy(size: newSize)
    }

    ///  Copies and crops an image to the supplied size.
    ///
    ///  - parameter size: The size of the new image.
    ///
    ///  - returns: The cropped copy of the given image.
    func crop(size: NSSize) -> NSImage? {
        // Resize the current image, while preserving the aspect ratio.
        guard let resized = resizeWhileMaintainingAspectRatioToSize(size: size) else {
            return nil
        }
        // Get some points to center the cropping area.
        let xCoord = floor((resized.width - size.width) / 2)
        let yCoord = floor((resized.height - size.height) / 2)

        // Create the cropping frame.
        let frame = NSRect(x: xCoord, y: yCoord, width: size.width, height: size.height)

        // Get the best representation of the image for the given cropping frame.
        guard let rep = resized.bestRepresentation(for: frame, context: nil, hints: nil) else {
            return nil
        }

        // Create a new image with the new size
        let img = NSImage(size: size)

        img.lockFocus()
        defer { img.unlockFocus() }

        if rep.draw(
            in: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            from: frame,
            operation: NSCompositingOperation.copy,
            fraction: 1.0,
            respectFlipped: false,
            hints: [:]
        ) {
            // Return the cropped image.
            return img
        }

        // Return nil in case anything fails.
        return nil
    }

    ///  Saves the PNG representation of the current image to the HD.
    ///
    /// - parameter url: The location url to which to write the png file.
    func savePNGRepresentationToURL(url: URL) throws {
            guard let tiffData = self.tiffRepresentation,
                  // Create an NSBitmapImageRep object using TIFF data
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  // Converts an NSBitmapImageRep object to PNG data
                  let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "Error creating PNG representation", code: 0, userInfo: nil)
            }
            // Writes PNG data to the specified URL
            try pngData.write(to: url, options: .atomicWrite)
        }

    func saveJPEGRepresentationToURL(url: URL) throws {
        if let jpeg = JPEGRepresentation {
            try jpeg.write(to: url, options: .atomicWrite)
        }
    }

    func resize(to targetSize: CGSize) -> NSImage? {
        let frame = CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height)
        guard let representation = bestRepresentation(for: frame, context: nil, hints: nil) else {
            return nil
        }
        let image = NSImage(size: targetSize, flipped: false, drawingHandler: { _ -> Bool in
            representation.draw(in: frame)
        })
        return image
    }

    func resized(to newSize: NSSize) -> NSImage? {
        if let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(newSize.width), pixelsHigh: Int(newSize.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) {
            bitmapRep.size = newSize
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
            let rect = NSRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
            draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()

            let resizedImage = NSImage(size: newSize)
            resizedImage.addRepresentation(bitmapRep)
            return resizedImage
        }

        return nil
    }

    /// Copy the image and resize it to the supplied size, while maintaining it's
    /// original aspect ratio.
    ///
    /// - Parameter targetSize:
    /// - Returns: The resized image.
    func resizeMaintainingAspectRatio(to targetSize: CGSize) -> NSImage? {
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let ratio = max(widthRatio, heightRatio)
        let newSize = CGSize(width: floor(size.width * ratio), height: floor(size.height * ratio))
        return resized(to: NSSize(width: newSize.width, height: newSize.height))
    }

    // MARK: Cropping

    /// Resize the image, to nearly fit the supplied cropping size
    /// and return a cropped copy the image.
    ///
    /// - Parameter targetSize:
    /// - Parameter targetSize:
    /// - Returns: The cropped image.
    func crop(to targetSize: CGSize) -> NSImage? {
        // Resize the current image, while preserving the aspect ratio.
        guard let resized = resizeMaintainingAspectRatio(to: targetSize) else {
            return nil
        }

        // Get some points to center the cropping area.
        let yCoord = floor(resized.size.height - targetSize.height)

        // Create the cropping frame.
        let frame = CGRect(origin: CGPoint(x: 0, y: yCoord), size: targetSize)

        // Get the best representation of the image for the given cropping frame.
        guard let representation = resized.bestRepresentation(for: frame, context: nil, hints: nil) else {
            return nil
        }

        // Create a new image with the new size
        let cropped = NSImage(size: targetSize)
        cropped.lockFocus()
        defer { cropped.unlockFocus() }

        let outputFrame = CGRect(origin: CGPoint(x: 0, y: 0), size: targetSize)

        guard representation.draw(in: outputFrame, from: frame, operation: .copy, fraction: 1.0, respectFlipped: false, hints: [:]) else {
            return nil
        }
        return cropped
    }

    var jpgData: Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation)
        else { return nil }

        return bitmapImage.representation(using: .jpeg, properties: [:])
    }

    func tint(color: NSColor) -> NSImage {
        if let image = copy() as? NSImage {
            image.lockFocus()

            color.set()

            let imageRect = NSRect(origin: .zero, size: image.size)
            imageRect.fill(using: .sourceAtop)
            image.unlockFocus()

            return image
        }

        return self
    }

    func roundCorners(withRadius radius: CGFloat) -> NSImage {
        let rect = NSRect(origin: NSPoint.zero, size: size)
        if
            let cgImage = cgImage,
            let context = CGContext(data: nil,
                                    width: Int(size.width),
                                    height: Int(size.height),
                                    bitsPerComponent: 8,
                                    bytesPerRow: 4 * Int(size.width),
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        {
            context.beginPath()
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.closePath()
            context.clip()
            context.draw(cgImage, in: rect)

            if let composedImage = context.makeImage() {
                return NSImage(cgImage: composedImage, size: size)
            }
        }

        return self
    }

    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return self.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
