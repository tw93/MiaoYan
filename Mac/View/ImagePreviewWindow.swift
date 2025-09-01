import Alamofire
import Cocoa

class ImagePreviewWindow: NSWindow {
    private var imageView: NSImageView!
    private var loadingIndicator: NSProgressIndicator!
    private var backgroundView: NSVisualEffectView!
    private var currentImageURL: String?
    private var fixedPosition: NSPoint?
    private var isPositionFixed: Bool = false

    // 图片缓存
    private static var imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 50  // 最多缓存50张图片
        cache.totalCostLimit = 100 * 1024 * 1024  // 100MB缓存
        return cache
    }()

    // 当前加载任务
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
        ignoresMouseEvents = true  // 忽略鼠标事件，避免干扰编辑器
        animationBehavior = .utilityWindow
        isExcludedFromWindowsMenu = true
        hidesOnDeactivate = false
    }

    private func setupUI() {
        // 毛玻璃背景
        backgroundView = NSVisualEffectView()
        backgroundView.material = .hudWindow
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 8
        backgroundView.layer?.masksToBounds = true
        contentView = backgroundView

        // 图片视图
        imageView = NSImageView()
        imageView.imageFrameStyle = .none
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = true  // 改为手动布局
        backgroundView.addSubview(imageView)

        // 加载指示器 - 使用更简洁的样式
        loadingIndicator = NSProgressIndicator()
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small  // 使用小尺寸
        loadingIndicator.isHidden = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = true
        backgroundView.addSubview(loadingIndicator)
    }

    func showPreview(for imageURL: String, at point: NSPoint, isFixed: Bool = false) {
        // 记录是否需要固定位置
        if !isPositionFixed || fixedPosition == nil {
            fixedPosition = point
            isPositionFixed = isFixed
        }

        guard imageURL != currentImageURL else {
            // 如果是同一个图片且位置固定，不需要调整位置
            if !isPositionFixed {
                repositionWindow(at: fixedPosition ?? point)
            }
            return
        }

        // 取消之前的加载任务
        currentLoadingTask?.cancel()
        currentLoadingTask = nil

        currentImageURL = imageURL
        hideImage()

        let displayPoint = fixedPosition ?? point

        // 先检查缓存
        if let cachedImage = Self.imageCache.object(forKey: imageURL as NSString) {
            // 缓存命中，直接显示
            displayImage(cachedImage, at: displayPoint)
            return
        }

        // 缓存未命中，显示轻量加载提示
        showLightLoading(at: displayPoint)

        // 开始加载图片
        loadImage(from: imageURL) { [weak self] image in
            DispatchQueue.main.async {
                guard self?.currentImageURL == imageURL else { return }

                if let image = image {
                    Self.imageCache.setObject(image, forKey: imageURL as NSString)
                    self?.displayImage(image, at: displayPoint)
                } else {
                    self?.hidePreview()
                }
            }
        }
    }

    private func loadImage(from imageURL: String, completion: @escaping (NSImage?) -> Void) {
        if imageURL.hasPrefix("http://") || imageURL.hasPrefix("https://") {
            // 远程图片
            loadRemoteImage(from: imageURL, completion: completion)
        } else if imageURL.hasPrefix("file://") {
            // 本地图片 (完整路径)
            let path = imageURL.replacingOccurrences(of: "file://", with: "")
            let image = NSImage(contentsOfFile: path)
            completion(image)
        } else {
            // 相对路径图片
            loadLocalImage(from: imageURL, completion: completion)
        }
    }

    private func loadRemoteImage(from url: String, completion: @escaping (NSImage?) -> Void) {
        // 使用URLSession替代Alamofire，添加超时控制
        guard let imageURL = URL(string: url) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: imageURL)
        request.timeoutInterval = 8.0  // 8秒超时
        request.cachePolicy = .returnCacheDataElseLoad  // 使用系统缓存

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer {
                self?.currentLoadingTask = nil
            }

            // 检查是否被取消
            if let error = error as NSError?, error.code == NSURLErrorCancelled {
                return
            }

            if let data = data, let image = NSImage(data: data) {
                completion(image)
            } else {
                completion(nil)
            }
        }

        currentLoadingTask = task
        task.resume()
    }

    private func loadLocalImage(from imagePath: String, completion: @escaping (NSImage?) -> Void) {
        guard let note = EditTextView.note else {
            completion(nil)
            return
        }

        // 尝试获取图片URL
        if let imageURL = note.getImageUrl(imageName: imagePath) {
            let image = NSImage(contentsOf: imageURL)
            completion(image)
        } else {
            // 尝试项目相对路径
            let projectPath = note.project.url.appendingPathComponent(imagePath)
            let image = NSImage(contentsOf: projectPath)
            completion(image)
        }
    }

    private func displayImage(_ image: NSImage, at point: NSPoint) {
        let finalSize = calculateImageSize(image)

        // 直接设置最终状态
        imageView.image = image
        imageView.frame = CGRect(x: 8, y: 8, width: finalSize.width, height: finalSize.height)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.layer?.backgroundColor = nil
        imageView.layer?.cornerRadius = 0

        // 隐藏加载指示器
        loadingIndicator.stopAnimation(nil)
        loadingIndicator.isHidden = true

        // 设置窗口大小
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


    // 计算图片尺寸的公共方法
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
        let offset: CGFloat = 15  // 距离链接的偏移量

        // 强制在上方显示（水平居中对齐）
        var windowPoint = NSPoint(
            x: point.x - windowSize.width / 2,  // 水平居中
            y: point.y + offset  // 始终在上方
        )

        // 如果左边超出屏幕，向右调整
        if windowPoint.x < screen.frame.minX {
            windowPoint.x = screen.frame.minX + 5
        }

        // 如果右边超出屏幕，向左调整
        if windowPoint.x + windowSize.width > screen.frame.maxX {
            windowPoint.x = screen.frame.maxX - windowSize.width - 5
        }

        // 强制保持在上方，即使超出屏幕也只调整到最大可见区域
        if windowPoint.y + windowSize.height > screen.frame.maxY {
            // 紧贴上边界，但仍保持在“上方”显示
            windowPoint.y = screen.frame.maxY - windowSize.height
        }
        setFrameOrigin(windowPoint)
    }

    // 轻量加载提示 - 简洁平面设计
    private func showLightLoading(at point: NSPoint) {
        // 更紧凑的加载窗口，适合并排布局
        let loadingSize = CGSize(width: 120, height: 40)
        setContentSize(loadingSize)

        // 清理图片视图
        imageView.image = nil
        imageView.frame = CGRect.zero
        imageView.layer?.backgroundColor = nil

        // 设置更小的加载指示器（并排左侧）
        loadingIndicator.isHidden = false
        loadingIndicator.startAnimation(nil)
        loadingIndicator.controlSize = .mini  // 使用最小尺寸
        loadingIndicator.frame = CGRect(
            x: 20,  // 左侧边距
            y: loadingSize.height / 2 - 8,  // 垂直居中
            width: 16,
            height: 16
        )

        // 添加并排的加载文字
        if backgroundView.subviews.count == 2 {
            let loadingLabel = NSTextField(labelWithString: "Loading...")
            loadingLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            loadingLabel.textColor = .secondaryLabelColor
            loadingLabel.alignment = .left
            loadingLabel.isBordered = false
            loadingLabel.isBezeled = false
            loadingLabel.isEditable = false
            loadingLabel.isSelectable = false
            loadingLabel.backgroundColor = .clear
            loadingLabel.frame = CGRect(
                x: 42,  // 紧跟加载指示器
                y: loadingSize.height / 2 - 8,  // 与加载指示器对齐
                width: 70,
                height: 16
            )
            backgroundView.addSubview(loadingLabel)
        }

        repositionWindow(at: point)

        // 快速淡入
        if !isVisible {
            alphaValue = 0
            makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12  // 更快的出现
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            })
        }
    }

    private func hideLoadingIndicator() {
        loadingIndicator.stopAnimation(nil)
        loadingIndicator.isHidden = true

        // 清理可能的加载文字
        if backgroundView.subviews.count > 2 {
            backgroundView.subviews.last?.removeFromSuperview()
        }
    }

    private func hideImage() {
        imageView.image = nil
    }

    func hidePreview() {
        // 取消正在进行的加载任务
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
                    context.duration = 0.15  // 快速淡出
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    animator().alphaValue = 0
                },
                completionHandler: {
                    self.orderOut(nil)
                    self.alphaValue = 1
                })
        }
    }

    // 重写 setContentSize 强制限制窗口大小
    override func setContentSize(_ size: NSSize) {
        let maxWidth: CGFloat = 520  // 绝对最大宽度（500 + 边距）
        let maxHeight: CGFloat = 520  // 绝对最大高度（500 + 边距）

        let limitedSize = NSSize(
            width: min(size.width, maxWidth),
            height: min(size.height, maxHeight)
        )
        super.setContentSize(limitedSize)
    }
}
