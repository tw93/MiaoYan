import AppKit

// MARK: - Toast Configuration
struct ToastConfiguration: Sendable {
    var animationDuration: TimeInterval = 1.5
    var fadeKeyTimes: [NSNumber] = [0, 0.05, 0.85, 1]
    var fadeValues: [Float] = [0, 0.92, 0.92, 0]
    var cornerRadius: CGFloat = 8
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 6
    var minWidth: CGFloat = 80
    var maxWidth: CGFloat = 420
    var minHeight: CGFloat = 20
    var iconSize: CGFloat = 14
    var iconSpacing: CGFloat = 5
    var iconVerticalOffset: CGFloat = 1.2

    static let `default` = ToastConfiguration()
}

public enum ToastStyle {
    case info
    case success
    case failure

    var symbolName: String? {
        switch self {
        case .info:
            return nil
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.circle.fill"
        }
    }

    var tintColor: NSColor {
        switch self {
        case .info:
            return .white
        case .success:
            return .white
        case .failure:
            return .white
        }
    }

    var fallbackSymbol: String {
        switch self {
        case .info:
            return ""
        case .success:
            return "☺︎"
        case .failure:
            return "☹︎"
        }
    }
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

    func updateToastMessage(_ message: String) {
        // Find the label in current toast and update it
        if let toast = currentToast {
            updateLabelInView(toast, with: message)
        }
    }

    private func updateLabelInView(_ view: NSView, with message: String) {
        for subview in view.subviews {
            if let label = subview as? NSTextField {
                label.stringValue = message
                return
            } else if let stack = subview as? NSStackView {
                for arrangedSubview in stack.arrangedSubviews {
                    if let label = arrangedSubview as? NSTextField {
                        label.stringValue = message
                        return
                    }
                }
            }
            // Recursively search in subviews
            updateLabelInView(subview, with: message)
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
        style: ToastStyle = .info,
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
                style: style,
                configuration: configuration)
        } else {
            return makeSimpleToast(
                container: container,
                message: message,
                style: style,
                configuration: configuration)
        }
    }

    @MainActor
    private static func makeSimpleToast(
        container: NSView,
        message: String,
        style: ToastStyle,
        configuration: ToastConfiguration
    ) -> NSView {
        let label = makeLabel(message)

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        row.addSubview(label)

        var constraints: [NSLayoutConstraint] = [
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: configuration.horizontalPadding),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -configuration.horizontalPadding),
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: configuration.verticalPadding),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -configuration.verticalPadding),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: configuration.minHeight + configuration.verticalPadding * 2),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor),
            label.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor),
        ]

        if let icon = makeStatusIcon(style: style, configuration: configuration) {
            row.addSubview(icon)
            constraints.append(contentsOf: [
                icon.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: configuration.iconSpacing),
            ])
        } else {
            constraints.append(label.leadingAnchor.constraint(equalTo: row.leadingAnchor))
        }

        NSLayoutConstraint.activate(constraints)
        return container
    }

    @MainActor
    private static func makeTitleToast(
        container: NSView,
        message: String,
        title: String,
        style: ToastStyle,
        configuration: ToastConfiguration
    ) -> NSView {
        let stack = makeContentStack(configuration: configuration)
        stack.orientation = .horizontal
        stack.alignment = .top

        if let icon = makeStatusIcon(style: style, configuration: configuration) {
            stack.addArrangedSubview(icon)
        }

        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        let titleLabel = makeLabel(title, isTitle: true)
        let messageLabel = makeLabel(message)

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(messageLabel)
        stack.addArrangedSubview(textStack)
        container.addSubview(stack)
        applyContentConstraints(stack: stack, in: container, configuration: configuration)

        return container
    }

    @MainActor
    private static func makeStatusIcon(style: ToastStyle, configuration: ToastConfiguration) -> NSView? {
        guard style != .info else { return nil }

        if let symbolName = style.symbolName,
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: configuration.iconSize, weight: .semibold)
            let configuredImage = image.withSymbolConfiguration(symbolConfig) ?? image
            let iconContainer = NSView()
            iconContainer.translatesAutoresizingMaskIntoConstraints = false
            let imageView = NSImageView(image: configuredImage)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentTintColor = style.tintColor
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.setContentHuggingPriority(.required, for: .horizontal)
            imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
            iconContainer.addSubview(imageView)

            NSLayoutConstraint.activate([
                iconContainer.widthAnchor.constraint(equalToConstant: configuration.iconSize),
                iconContainer.heightAnchor.constraint(equalToConstant: configuration.iconSize),
                imageView.widthAnchor.constraint(equalToConstant: configuration.iconSize),
                imageView.heightAnchor.constraint(equalToConstant: configuration.iconSize),
                imageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor, constant: configuration.iconVerticalOffset),
            ])
            return iconContainer
        }

        let fallback = NSTextField(labelWithString: style.fallbackSymbol)
        fallback.translatesAutoresizingMaskIntoConstraints = false
        fallback.textColor = style.tintColor
        fallback.font = .systemFont(ofSize: max(configuration.iconSize - 1, 12), weight: .regular)
        fallback.setContentHuggingPriority(.required, for: .horizontal)
        fallback.setContentCompressionResistancePriority(.required, for: .horizontal)
        return fallback
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

    @MainActor
    private static func makeContentStack(configuration: ToastConfiguration) -> NSStackView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = configuration.iconSpacing
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.setHuggingPriority(.required, for: .vertical)
        stack.setHuggingPriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        return stack
    }

    @MainActor
    private static func applyContentConstraints(stack: NSStackView, in container: NSView, configuration: ToastConfiguration) {
        let minHeight = configuration.minHeight + configuration.verticalPadding * 2

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: configuration.horizontalPadding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -configuration.horizontalPadding),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: configuration.verticalPadding),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -configuration.verticalPadding),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight),
        ])
    }
}

// MARK: - NSViewController Extension
extension NSViewController {
    @MainActor
    public func toast(message: String, title: String, style: ToastStyle = .info) {
        let toast = ToastFactory.makeToast(message: message, title: title, style: style)
        ToastManager.shared.showToast(toast, in: view)
    }

    @MainActor
    public func toast(message: String, duration: TimeInterval? = nil, style: ToastStyle = .info) {
        let toast = ToastFactory.makeToast(message: message, style: style)
        ToastManager.shared.showToast(toast, in: view, duration: duration)
    }

    @MainActor
    public func toastPersistent(message: String) {
        let toast = ToastFactory.makeToast(message: message)
        ToastManager.shared.showToast(toast, in: view, persistent: true)
    }

    @MainActor
    public func toastUpdate(message: String) {
        ToastManager.shared.updateToastMessage(message)
    }

    @MainActor
    public func toastDismiss() {
        ToastManager.shared.dismissCurrentToast()
    }
}
