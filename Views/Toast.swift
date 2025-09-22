import AppKit

// MARK: - Toast Configuration
struct ToastConfiguration: Sendable {
    var animationDuration: TimeInterval = 3.0
    var fadeKeyTimes: [NSNumber] = [0, 0.05, 0.85, 1]
    var fadeValues: [Float] = [0, 0.92, 0.92, 0]
    var cornerRadius: CGFloat = 8
    var padding: CGFloat = 8
    var minWidth: CGFloat = 80
    var maxWidth: CGFloat = 420
    var minHeight: CGFloat = 20
    var iconSize: CGFloat = 44
    var iconSpacing: CGFloat = 6

    static let `default` = ToastConfiguration()
}

// MARK: - Toast Manager
@MainActor
final class ToastManager {

    static let shared = ToastManager()

    private let configuration: ToastConfiguration
    private var currentToast: NSView?
    private var currentAnimationLayer: CALayer?

    init(configuration: ToastConfiguration = .default) {
        self.configuration = configuration
    }

    func showToast(
        _ toast: NSView,
        in container: NSView,
        persistent: Bool = false,
        duration: TimeInterval? = nil
    ) {

        dismissCurrentToast()

        prepareToastViewHierarchy(toast, in: container)
        currentToast = toast
        currentAnimationLayer = toast.layer

        if persistent {
            toast.layer?.opacity = 0.92
        } else {
            animateToastFade(
                toast,
                duration: duration ?? configuration.animationDuration)
        }
    }

    func dismissCurrentToast() {
        if let layer = currentAnimationLayer {
            layer.removeAllAnimations()
        }
        currentAnimationLayer = nil

        currentToast?.removeFromSuperview()
        currentToast = nil
    }

    // MARK: - Private

    private func prepareToastViewHierarchy(_ toast: NSView, in view: NSView) {
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.wantsLayer = true
        if toast.layer == nil { toast.layer = CALayer() }
        toast.layer?.cornerRadius = configuration.cornerRadius
        toast.layer?.masksToBounds = true
        toast.layer?.opacity = 0

        if !toast.subviews.contains(where: { $0.wantsLayer && $0.layer?.backgroundColor != nil }) {
            let backgroundView = NSView()
            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.wantsLayer = true
            backgroundView.layer = CALayer()
            backgroundView.layer?.backgroundColor = Theme.toastBackgroundColor.cgColor
            backgroundView.layer?.cornerRadius = configuration.cornerRadius

            toast.addSubview(backgroundView, positioned: .below, relativeTo: nil)
            NSLayoutConstraint.activate([
                backgroundView.leadingAnchor.constraint(equalTo: toast.leadingAnchor),
                backgroundView.trailingAnchor.constraint(equalTo: toast.trailingAnchor),
                backgroundView.topAnchor.constraint(equalTo: toast.topAnchor),
                backgroundView.bottomAnchor.constraint(equalTo: toast.bottomAnchor),
            ])
        }

        view.addSubview(toast)

        let minW = toast.widthAnchor.constraint(greaterThanOrEqualToConstant: configuration.minWidth)
        let maxW = toast.widthAnchor.constraint(lessThanOrEqualToConstant: configuration.maxWidth)
        minW.priority = .defaultHigh
        maxW.priority = .required

        NSLayoutConstraint.activate([
            toast.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            toast.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -32),
            toast.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: 32),
            minW, maxW,
        ])
    }

    private func animateToastFade(_ toast: NSView, duration: TimeInterval) {
        guard let layer = toast.layer else { return }

        layer.opacity = 0

        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = configuration.fadeValues
        anim.keyTimes = configuration.fadeKeyTimes
        anim.duration = duration
        anim.isRemovedOnCompletion = true
        anim.fillMode = .removed
        anim.calculationMode = .linear

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak toast] in
            guard let self, let toast else { return }
            toast.removeFromSuperview()
            if self.currentToast == toast {
                self.currentToast = nil
                self.currentAnimationLayer = nil
            }
        }
        layer.add(anim, forKey: "toast.opacity")
        CATransaction.commit()
    }
}

// MARK: - Toast Factory
enum ToastFactory {

    @MainActor
    static func makeToast(
        message: String,
        title: String? = nil,
        configuration: ToastConfiguration = .default
    ) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer = CALayer()
        container.layer?.cornerRadius = configuration.cornerRadius
        container.layer?.masksToBounds = true

        if let title {
            return makeTitleToast(
                container: container,
                message: message,
                title: title,
                configuration: configuration)
        } else {
            return makeSimpleToast(
                container: container,
                message: message,
                configuration: configuration)
        }
    }

    @MainActor
    private static func makeSimpleToast(
        container: NSView,
        message: String,
        configuration: ToastConfiguration
    ) -> NSView {
        let label = makeLabel(message)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: configuration.padding),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -configuration.padding),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: configuration.padding),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -configuration.padding),

            label.heightAnchor.constraint(greaterThanOrEqualToConstant: configuration.minHeight),
        ])
        return container
    }

    @MainActor
    private static func makeTitleToast(
        container: NSView,
        message: String,
        title: String,
        configuration: ToastConfiguration
    ) -> NSView {
        let titleLabel = makeLabel(title, isTitle: true)
        let messageLabel = makeLabel(message)

        container.addSubview(titleLabel)
        container.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: configuration.padding),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -configuration.padding),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: configuration.padding),

            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            messageLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -configuration.padding),

            titleLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: configuration.minHeight),
            messageLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: configuration.minHeight),
        ])

        return container
    }

    @MainActor
    private static func makeLabel(_ text: String, isTitle: Bool = false) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.textColor = Theme.toastTextColor
        tf.lineBreakMode = .byWordWrapping
        tf.maximumNumberOfLines = 0
        tf.alignment = .left
        tf.setContentCompressionResistancePriority(.required, for: .horizontal)
        tf.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        tf.font = isTitle ? .boldSystemFont(ofSize: 14) : .systemFont(ofSize: 13)
        return tf
    }
}

// MARK: - NSViewController Extension
extension NSViewController {
    @MainActor
    public func toast(message: String, title: String) {
        let toast = ToastFactory.makeToast(message: message, title: title)
        ToastManager.shared.showToast(toast, in: view)
    }

    @MainActor
    public func toast(message: String, duration: TimeInterval? = nil) {
        let toast = ToastFactory.makeToast(message: message)
        ToastManager.shared.showToast(toast, in: view, duration: duration)
    }

    @MainActor
    public func toastPersistent(message: String) {
        let toast = ToastFactory.makeToast(message: message)
        ToastManager.shared.showToast(toast, in: view, persistent: true)
    }

    @MainActor
    public func toastDismiss() {
        ToastManager.shared.dismissCurrentToast()
    }
}
