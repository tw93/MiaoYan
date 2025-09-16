import AppKit

private var currentToast: NSView?

// MARK: - Toast Manager
// MARK: - Toast Configuration
struct ToastConfiguration {
    let animationDuration: TimeInterval
    let fadeKeyTimes: [NSNumber]
    let fadeValues: [Float]
    let cornerRadius: CGFloat
    let padding: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let minHeight: CGFloat
    let iconSize: CGFloat
    let iconSpacing: CGFloat

    static let `default` = ToastConfiguration(
        animationDuration: 3.0,
        fadeKeyTimes: [0, 0.01, 0.8, 1],
        fadeValues: [0, 0.8, 0.8, 0],
        cornerRadius: 8,
        padding: 5,
        minWidth: 50,
        maxWidth: 420,
        minHeight: 17,
        iconSize: 50,
        iconSpacing: 5
    )
}

class ToastManager {
    static let shared = ToastManager()

    private let configuration: ToastConfiguration

    init(configuration: ToastConfiguration = .default) {
        self.configuration = configuration
    }

    func showToast(_ toast: NSView, in view: NSView, persistent: Bool = false) {
        dismissCurrentToast()
        currentToast = toast

        setupToastConstraints(toast: toast, in: view)

        if !persistent {
            animateToastFade(toast)
        } else {
            toast.layer?.opacity = 0.8
        }
    }

    func dismissCurrentToast() {
        currentToast?.removeFromSuperview()
        currentToast = nil
    }

    private func setupToastConstraints(toast: NSView, in view: NSView) {
        view.addSubview(toast)

        NSLayoutConstraint.activate([
            toast.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            toast.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -32),
            toast.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: 32),
        ])
    }

    private func animateToastFade(_ toast: NSView) {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = configuration.fadeValues
        animation.keyTimes = configuration.fadeKeyTimes
        animation.duration = configuration.animationDuration
        animation.isAdditive = true

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            toast.removeFromSuperview()
            if currentToast == toast {
                currentToast = nil
            }
        }
        toast.layer?.add(animation, forKey: "opacity")
        CATransaction.commit()
    }
}

// MARK: - Toast Factory
class ToastFactory {
    static func makeToast(message: String, title: String? = nil, configuration: ToastConfiguration = .default) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer = createToastLayer(configuration: configuration)
        container.translatesAutoresizingMaskIntoConstraints = false

        if let title = title {
            return createTitleToast(container: container, message: message, title: title, configuration: configuration)
        } else {
            return createSimpleToast(container: container, message: message, configuration: configuration)
        }
    }

    private static func createToastLayer(configuration: ToastConfiguration) -> CALayer {
        let layer = CALayer()
        layer.backgroundColor = NSColor.black.withAlphaComponent(1).cgColor
        layer.cornerRadius = configuration.cornerRadius
        layer.opacity = 0.0
        return layer
    }

    private static func createSimpleToast(container: NSView, message: String, configuration: ToastConfiguration) -> NSView {
        let messageLabel = createTextLabel(message: message)
        container.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: configuration.padding),
            messageLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -configuration.padding),
            messageLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: configuration.padding),
            messageLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -configuration.padding),
            messageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: configuration.minWidth),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: configuration.maxWidth),
            messageLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: configuration.minHeight),
        ])

        return container
    }

    private static func createTitleToast(container: NSView, message: String, title: String, configuration: ToastConfiguration) -> NSView {
        let titleLabel = createTextLabel(message: title)
        let messageLabel = createTextLabel(message: message)

        container.addSubview(titleLabel)
        container.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: configuration.iconSize + configuration.iconSpacing * 2),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -configuration.padding),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: configuration.padding),
            titleLabel.heightAnchor.constraint(equalToConstant: configuration.minHeight),
            titleLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300),

            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            messageLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -configuration.padding),
            messageLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: configuration.minHeight),
            messageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
        ])

        return container
    }

    private static func createTextLabel(message: String) -> NSTextField {
        let textField = NSTextField()
        textField.stringValue = message
        textField.translatesAutoresizingMaskIntoConstraints = false

        // Styling
        textField.textColor = .white
        textField.drawsBackground = false
        textField.isBordered = false
        textField.focusRingType = .none
        textField.isEditable = false
        textField.isSelectable = false
        textField.alignment = .left

        return textField
    }
}

// MARK: - NSViewController Extension
extension NSViewController {
    public func toast(message: String, title: String) {
        let toast = ToastFactory.makeToast(message: message, title: title)
        ToastManager.shared.showToast(toast, in: view)
    }

    public func toast(message: String) {
        let toast = ToastFactory.makeToast(message: message)
        ToastManager.shared.showToast(toast, in: view)
    }

    public func toastPersistent(message: String) {
        let toast = ToastFactory.makeToast(message: message)
        ToastManager.shared.showToast(toast, in: view, persistent: true)
    }

    public func toastDismiss() {
        ToastManager.shared.dismissCurrentToast()
    }
}

