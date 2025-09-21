import Cocoa

class ImagePreviewWindow: NSWindow {
    private var imageView: NSImageView!
    private var loadingIndicator: NSProgressIndicator!
    private var backgroundView: NSVisualEffectView!
    private var currentImageURL: String?
    private var fixedPosition: NSPoint?
    private var isPositionFixed: Bool = false

    private static var imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 50
        cache.totalCostLimit = 100 * 1024 * 1024
        return cache
    }()

    private var currentLoadingTask: URLSessionDataTask?

    init() {
        let contentRect = NSRect(x: 0, y: 0, width: 300, height: 200)
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)

        setupWindow()
        setupUI()
    }

    private func setupWindow() {
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        animationBehavior = .utilityWindow
        isExcludedFromWindowsMenu = true
        hidesOnDeactivate = false
    }

    private func setupUI() {
        backgroundView = NSVisualEffectView()
        backgroundView.material = .hudWindow
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 8
        backgroundView.layer?.masksToBounds = true
        contentView = backgroundView

        imageView = NSImageView()
        imageView.imageFrameStyle = .none
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = true
        backgroundView.addSubview(imageView)

        loadingIndicator = NSProgressIndicator()
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isHidden = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = true
        backgroundView.addSubview(loadingIndicator)
    }

    func showPreview(for imageURL: String, at point: NSPoint, isFixed: Bool = false) {
        if !isPositionFixed || fixedPosition == nil {
            fixedPosition = point
            isPositionFixed = isFixed
        }

        guard imageURL != currentImageURL else {
            if !isPositionFixed {
                repositionWindow(at: fixedPosition ?? point)
            }
            return
        }

        currentLoadingTask?.cancel()
        currentLoadingTask = nil

        currentImageURL = imageURL
        hideImage()

        let displayPoint = fixedPosition ?? point

        if let cachedImage = Self.imageCache.object(forKey: imageURL as NSString) {
            displayImage(cachedImage, at: displayPoint)
            return
        }

        showLightLoading(at: displayPoint)

        loadImage(from: imageURL) { [weak self] image in
            DispatchQueue.main.async {
                guard self?.currentImageURL == imageURL else { return }

                self?.hideLoadingIndicator()

                if let image = image {
                    Self.imageCache.setObject(image, forKey: imageURL as NSString)
                    self?.displayImage(image, at: displayPoint)
                } else {
                    self?.hidePreview()
                }
            }
        }
    }

    private func loadImage(from imageURL: String, completion: @escaping @Sendable (NSImage?) -> Void) {
        if imageURL.hasPrefix("http://") || imageURL.hasPrefix("https://") {
            loadRemoteImage(from: imageURL, completion: completion)
        } else if imageURL.hasPrefix("file://") {
            let path = imageURL.replacingOccurrences(of: "file://", with: "")
            let image = NSImage(contentsOfFile: path)
            completion(image)
        } else {
            loadLocalImage(from: imageURL, completion: completion)
        }
    }

    private func loadRemoteImage(from url: String, completion: @escaping @Sendable (NSImage?) -> Void) {
        // Use URLSession with explicit timeout instead of Alamofire
        guard let imageURL = URL(string: url) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: imageURL)
        request.timeoutInterval = 8.0
        request.cachePolicy = .returnCacheDataElseLoad

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            Task { @MainActor [weak self] in
                defer {
                    self?.currentLoadingTask = nil
                }

                if let error = error as NSError?, error.code == NSURLErrorCancelled {
                    return
                }

                if let data = data, let image = NSImage(data: data) {
                    completion(image)
                } else {
                    completion(nil)
                }
            }
        }

        currentLoadingTask = task
        task.resume()
    }

    private func loadLocalImage(from imagePath: String, completion: @escaping @Sendable (NSImage?) -> Void) {
        guard let note = EditTextView.note else {
            completion(nil)
            return
        }

        if let imageURL = note.getImageUrl(imageName: imagePath) {
            let image = NSImage(contentsOf: imageURL)
            completion(image)
        } else {
            let projectPath = note.project.url.appendingPathComponent(imagePath)
            let image = NSImage(contentsOf: projectPath)
            completion(image)
        }
    }

    private func displayImage(_ image: NSImage, at point: NSPoint) {
        let finalSize = calculateImageSize(image)

        imageView.image = image
        imageView.frame = CGRect(x: 8, y: 8, width: finalSize.width, height: finalSize.height)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.layer?.backgroundColor = nil
        imageView.layer?.cornerRadius = 0

        loadingIndicator.stopAnimation(nil)
        loadingIndicator.isHidden = true

        let windowSize = CGSize(width: finalSize.width + 16, height: finalSize.height + 16)
        setContentSize(windowSize)

        repositionWindow(at: point)

        if !isVisible {
            alphaValue = 0
            makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            })
        }
    }

    private func calculateImageSize(_ image: NSImage) -> CGSize {
        let maxLongSide: CGFloat = 500
        let minShortSide: CGFloat = 100

        var finalWidth: CGFloat
        var finalHeight: CGFloat

        if let imageRep = image.representations.first {
            let pixelWidth = CGFloat(imageRep.pixelsWide)
            let pixelHeight = CGFloat(imageRep.pixelsHigh)

            if pixelWidth > 0 && pixelHeight > 0 {
                let aspectRatio = pixelWidth / pixelHeight

                if pixelWidth >= pixelHeight {
                    finalWidth = maxLongSide
                    finalHeight = maxLongSide / aspectRatio

                    if finalHeight < minShortSide {
                        finalHeight = minShortSide
                        finalWidth = minShortSide * aspectRatio
                    }
                } else {
                    finalHeight = maxLongSide
                    finalWidth = maxLongSide * aspectRatio

                    if finalWidth < minShortSide {
                        finalWidth = minShortSide
                        finalHeight = minShortSide / aspectRatio
                    }
                }
            } else {
                finalWidth = 360
                finalHeight = 360
            }
        } else {
            finalWidth = 360
            finalHeight = 360
        }

        return CGSize(width: finalWidth, height: finalHeight)
    }

    private func repositionWindow(at point: NSPoint) {
        guard let screen = NSScreen.main else { return }

        let windowSize = frame.size
        let offset: CGFloat = 15

        var windowPoint = NSPoint(
            x: point.x - windowSize.width / 2,
            y: point.y + offset
        )

        if windowPoint.x < screen.frame.minX {
            windowPoint.x = screen.frame.minX + 5
        }

        if windowPoint.x + windowSize.width > screen.frame.maxX {
            windowPoint.x = screen.frame.maxX - windowSize.width - 5
        }

        // Keep the window above the cursor while clamping to the visible area
        if windowPoint.y + windowSize.height > screen.frame.maxY {
            windowPoint.y = screen.frame.maxY - windowSize.height
        }
        setFrameOrigin(windowPoint)
    }

    private func showLightLoading(at point: NSPoint) {
        let loadingSize = CGSize(width: 120, height: 40)
        setContentSize(loadingSize)

        imageView.image = nil
        imageView.frame = CGRect.zero
        imageView.layer?.backgroundColor = nil

        loadingIndicator.isHidden = false
        loadingIndicator.startAnimation(nil)
        loadingIndicator.controlSize = .mini
        loadingIndicator.frame = CGRect(
            x: 20,
            y: loadingSize.height / 2 - 8,
            width: 16,
            height: 16
        )

        let hasLoadingLabel = backgroundView.subviews.contains { $0 is NSTextField }
        if !hasLoadingLabel {
            let loadingLabel = NSTextField(labelWithString: "Loading...")
            loadingLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            loadingLabel.textColor = Theme.secondaryTextColor
            loadingLabel.alignment = .left
            loadingLabel.isBordered = false
            loadingLabel.isBezeled = false
            loadingLabel.isEditable = false
            loadingLabel.isSelectable = false
            loadingLabel.backgroundColor = .clear
            loadingLabel.frame = CGRect(
                x: 42,
                y: loadingSize.height / 2 - 8,
                width: 70,
                height: 16
            )
            backgroundView.addSubview(loadingLabel)
        }

        repositionWindow(at: point)

        if !isVisible {
            alphaValue = 0
            makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            })
        }
    }

    private func hideLoadingIndicator() {
        loadingIndicator.stopAnimation(nil)
        loadingIndicator.isHidden = true

        backgroundView.subviews.removeAll { $0 is NSTextField }
    }

    private func hideImage() {
        imageView.image = nil
    }

    func hidePreview() {
        currentLoadingTask?.cancel()
        currentLoadingTask = nil

        currentImageURL = nil
        fixedPosition = nil
        isPositionFixed = false
        hideLoadingIndicator()
        hideImage()

        if isVisible {
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    animator().alphaValue = 0
                },
                completionHandler: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.orderOut(nil)
                        self?.alphaValue = 1
                    }
                })
        }
    }

    func isPointInToleranceArea(_ screenPoint: NSPoint, originalPoint: NSPoint) -> Bool {
        guard isVisible else { return false }

        let windowFrame = frame
        if windowFrame.contains(screenPoint) {
            return true
        }

        let tolerance: CGFloat = 50
        let toleranceRect = NSRect(
            x: originalPoint.x - tolerance,
            y: originalPoint.y - tolerance,
            width: tolerance * 2,
            height: tolerance * 2
        )

        return toleranceRect.contains(screenPoint)
    }

    override func setContentSize(_ size: NSSize) {
        let maxWidth: CGFloat = 520
        let maxHeight: CGFloat = 520

        let limitedSize = NSSize(
            width: min(size.width, maxWidth),
            height: min(size.height, maxHeight)
        )
        super.setContentSize(limitedSize)
    }
}
