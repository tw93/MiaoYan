import AppKit

extension NSImage {
    public var height: CGFloat { size.height }
    public var width: CGFloat { size.width }

    public var PNGRepresentation: Data? {
        guard let tiff = tiffRepresentation,
            let tiffData = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return tiffData.representation(using: .png, properties: [:])
    }

    public var JPEGRepresentation: Data? {
        guard let tiff = tiffRepresentation,
            let tiffData = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return tiffData.representation(using: .jpeg, properties: [:])
    }

    public func copy(size: NSSize) -> NSImage? {
        let frame = NSRect(origin: .zero, size: size)
        guard let rep = bestRepresentation(for: frame, context: nil, hints: nil) else {
            return nil
        }

        let img = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }

        return rep.draw(in: frame) ? img : nil
    }

    public func resizeWhileMaintainingAspectRatioToSize(size: NSSize) -> NSImage? {
        let widthRatio = size.width / width
        let heightRatio = size.height / height
        let ratio = max(widthRatio, heightRatio)

        let newSize = NSSize(
            width: floor(width * ratio),
            height: floor(height * ratio)
        )

        return copy(size: newSize)
    }

    public func crop(size: NSSize) -> NSImage? {
        guard let resized = resizeWhileMaintainingAspectRatioToSize(size: size) else {
            return nil
        }

        let xCoord = floor((resized.width - size.width) / 2)
        let yCoord = floor((resized.height - size.height) / 2)
        let frame = NSRect(x: xCoord, y: yCoord, width: size.width, height: size.height)

        guard let rep = resized.bestRepresentation(for: frame, context: nil, hints: nil) else {
            return nil
        }

        let img = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }

        let outputFrame = NSRect(origin: .zero, size: size)
        return rep.draw(
            in: outputFrame,
            from: frame,
            operation: .copy,
            fraction: 1.0,
            respectFlipped: false,
            hints: [:]
        ) ? img : nil
    }

    public func savePNGRepresentationToURL(url: URL) throws {
        guard let pngData = PNGRepresentation else {
            throw NSError(domain: "Error creating PNG representation", code: 0, userInfo: nil)
        }
        try pngData.write(to: url, options: .atomicWrite)
    }

    public func saveJPEGRepresentationToURL(url: URL) throws {
        guard let jpegData = JPEGRepresentation else {
            throw NSError(domain: "Error creating JPEG representation", code: 0, userInfo: nil)
        }
        try jpegData.write(to: url, options: .atomicWrite)
    }

    public func resize(to targetSize: CGSize) -> NSImage? {
        let frame = CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height)
        guard let representation = bestRepresentation(for: frame, context: nil, hints: nil) else {
            return nil
        }
        let image = NSImage(
            size: targetSize, flipped: false,
            drawingHandler: { _ -> Bool in
                representation.draw(in: frame)
            })
        return image
    }

    public func resized(to newSize: NSSize) -> NSImage? {
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
    public func resizeMaintainingAspectRatio(to targetSize: CGSize) -> NSImage? {
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
    public func crop(to targetSize: CGSize) -> NSImage? {
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

    public var jpgData: Data? {
        guard let tiffRepresentation = tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffRepresentation)
        else { return nil }

        return bitmapImage.representation(using: .jpeg, properties: [:])
    }

    public func tint(color: NSColor) -> NSImage {
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

    public func roundCorners(withRadius radius: CGFloat) -> NSImage {
        let rect = NSRect(origin: NSPoint.zero, size: size)
        if let cgImage = cgImage,
            let context = CGContext(
                data: nil,
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

    public var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return self.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
