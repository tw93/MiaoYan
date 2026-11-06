import AppKit

// MARK: - Toast Configuration
struct ToastConfiguration: Sendable {
    /// A short toast ("Saved") stays this long, fades included.
    var minimumDuration: TimeInterval = 1.5
    /// A long sentence never holds the corner longer than this.
    var maximumDuration: TimeInterval = 6
    /// A toast with an action (Undo) stays long enough to reach it.
    var actionDuration: TimeInterval = 5
    /// After the pointer leaves a toast it stays this long before fading.
    var hoverLinger: TimeInterval = 1
    var opacity: Float = 0.92
    var cornerRadius: CGFloat = 12
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 6
    var minWidth: CGFloat = 80
    var maxWidth: CGFloat = 420
    var minHeight: CGFloat = 20
    var iconSize: CGFloat = 14
    var iconSpacing: CGFloat = 5
    var iconVerticalOffset: CGFloat = 1.2

    static let `default` = ToastConfiguration()

    /// How long a message stays readable. A 1.5 s toast left about 1.2 s to
    /// read "This note no longer exists on disk, so edits are not saved", so
    /// the time grows with the text: a Han or kana character counts as one
    /// unit, any other character as half, at 80 ms a unit.
    func readingDuration(for text: String) -> TimeInterval {
        let units = text.unicodeScalars.reduce(0.0) { sum, scalar in
            sum + (scalar.properties.isIdeographic || (0x3040...0x30FF).contains(scalar.value) ? 1 : 0.5)
        }
        return min(maximumDuration, max(minimumDuration, 1 + units * 0.08))
    }
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
}

// MARK: - Toast Manager
@MainActor
final class ToastManager {

    static let shared = ToastManager()

    private let configuration: ToastConfiguration
    private var currentToast: NSView?
    private var currentAnimationLayer: CALayer?
    private var pendingFade: DispatchWorkItem?

    init(configuration: ToastConfiguration = .default) {
        self.configuration = configuration
    }

    func showToast(
        _ toast: NSView,
        in container: NSView,
        persistent: Bool = false,
        duration: TimeInterval? = nil,
        message: String? = nil
    ) {

        dismissCurrentToast()

        prepareToastViewHierarchy(toast, in: container)
        currentToast = toast
        currentAnimationLayer = toast.layer

        if persistent {
            toast.layer?.opacity = configuration.opacity
        } else {
            let hold = duration ?? message.map { configuration.readingDuration(for: $0) } ?? configuration.minimumDuration
            show(toast, for: hold)
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

    /// Dismisses `toast` only while it is still the one on screen.
    func dismiss(_ toast: NSView?) {
        guard let toast, toast === currentToast else { return }
        dismissCurrentToast()
    }

    func dismissCurrentToast() {
        pendingFade?.cancel()
        pendingFade = nil
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

        if !toast.subviews.contains(where: { $0.identifier?.rawValue == "ToastBackgroundView" }) {
            let backgroundView: NSView
            // Use the translucent system material only in dark mode, where the
            // .hudWindow glass renders as a rich dark frost over the dark
            // editor. In light mode the same material blends the bright window
            // content through .withinWindow and washes out to a flat gray (even
            // when pinned dark), so the fixed white label looks muddy. Fall back
            // to the solid dark pill there for a clean, consistent toast.
            if Theme.usesModernSystemChrome && view.effectiveAppearance.isDark {
                let effectView = NSVisualEffectView()
                effectView.material = .hudWindow
                effectView.blendingMode = .withinWindow
                effectView.state = .active
                effectView.appearance = NSAppearance(named: .darkAqua)
                effectView.wantsLayer = true
                backgroundView = effectView
            } else {
                let plainView = NSView()
                plainView.wantsLayer = true
                plainView.layer = CALayer()
                plainView.layer?.backgroundColor = Theme.toastBackgroundColor.cgColor
                backgroundView = plainView
            }

            backgroundView.identifier = NSUserInterfaceItemIdentifier("ToastBackgroundView")
            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.layer?.cornerRadius = configuration.cornerRadius
            backgroundView.layer?.borderWidth = Theme.usesModernSystemChrome ? 0.5 : 0
            // The toast surface is always dark (pinned dark glass above, fixed
            // dark fill below), so resolve the hairline against a dark
            // appearance too. Otherwise the light-mode window appearance makes
            // the border fade out and the toast loses the subtle edge it has in
            // dark mode.
            let toastBorderAppearance = NSAppearance(named: .darkAqua) ?? view.effectiveAppearance
            backgroundView.layer?.borderColor = Theme.panelHairlineColor.resolvedColor(for: toastBorderAppearance).cgColor

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

    /// Fades the toast in, holds it, then fades it out. The pointer resting
    /// on it holds it in place; leaving starts a short linger, then the fade.
    private func show(_ toast: NSView, for duration: TimeInterval) {
        guard let layer = toast.layer else { return }

        toast.layer?.borderWidth = Theme.usesModernSystemChrome ? 0 : 0.5
        toast.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        animateOpacity(layer, to: configuration.opacity, duration: Theme.Motion.feedback)
        scheduleFadeOut(toast, after: max(0, duration - Theme.Motion.change))

        (toast as? ToastContainerView)?.onHoverChange = { [weak self, weak toast] inside in
            guard let self, let toast, self.currentToast === toast else { return }
            if inside {
                self.pendingFade?.cancel()
                self.pendingFade = nil
                layer.removeAllAnimations()
                layer.opacity = self.configuration.opacity
            } else {
                self.scheduleFadeOut(toast, after: self.configuration.hoverLinger)
            }
        }
    }

    private func scheduleFadeOut(_ toast: NSView, after delay: TimeInterval) {
        pendingFade?.cancel()
        let work = DispatchWorkItem { [weak self, weak toast] in
            guard let self, let toast, self.currentToast === toast, let layer = toast.layer else { return }
            self.animateOpacity(layer, to: 0, duration: Theme.Motion.change)
            let removal = DispatchWorkItem { [weak self, weak toast] in
                guard let self, let toast, self.currentToast === toast else { return }
                toast.removeFromSuperview()
                self.currentToast = nil
                self.currentAnimationLayer = nil
                self.pendingFade = nil
            }
            self.pendingFade = removal
            DispatchQueue.main.asyncAfter(deadline: .now() + Theme.Motion.change, execute: removal)
        }
        pendingFade = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func animateOpacity(_ layer: CALayer, to value: Float, duration: TimeInterval) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = layer.presentation()?.opacity ?? layer.opacity
        anim.toValue = value
        anim.duration = duration
        anim.timingFunction = Theme.Motion.curve
        layer.opacity = value
        layer.add(anim, forKey: "toast.opacity")
    }
}

/// The toast's own view: it reports the pointer entering and leaving, so a
/// message being read stays put, and it lets an action button take a click.
final class ToastContainerView: NSView {
    var onHoverChange: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
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
        let container = ToastContainerView()
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

    /// A one-line toast with a text button after the message (Undo).
    @MainActor
    static func makeActionToast(
        message: String,
        actionTitle: String,
        configuration: ToastConfiguration = .default,
        action: @escaping () -> Void
    ) -> NSView {
        let container = makeToast(message: message, configuration: configuration)
        guard let row = container.subviews.first,
            let label = row.subviews.compactMap({ $0 as? NSTextField }).first
        else { return container }

        let button = ToastActionButton(title: actionTitle, action: action)
        row.addSubview(button)
        if let trailing = row.constraints.first(where: { ($0.firstItem as? NSTextField) === label && $0.firstAttribute == .trailing }) {
            trailing.isActive = false
        }
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 12),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            button.firstBaselineAnchor.constraint(equalTo: label.firstBaselineAnchor),
        ])
        return container
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

        // No symbol image: show the message alone rather than a text emoticon.
        return nil
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

/// The text button inside an action toast. It runs its action once and
/// closes the toast, the way a toast's Undo does on iPhone.
final class ToastActionButton: NSButton {
    private var handler: (() -> Void)?

    convenience init(title: String, action: @escaping () -> Void) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        setButtonType(.momentaryChange)
        handler = action
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: Theme.toastTextColor,
            ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        target = self
        self.action = #selector(run)
    }

    @objc private func run() {
        let handler = self.handler
        self.handler = nil
        ToastManager.shared.dismissCurrentToast()
        handler?()
    }
}

// MARK: - NSViewController Extension
extension NSViewController {
    @MainActor
    public func toast(message: String, title: String, style: ToastStyle = .info) {
        let toast = ToastFactory.makeToast(message: message, title: title, style: style)
        ToastManager.shared.showToast(toast, in: view, message: title + message)
    }

    @MainActor
    public func toast(message: String, duration: TimeInterval? = nil, style: ToastStyle = .info) {
        let toast = ToastFactory.makeToast(message: message, style: style)
        ToastManager.shared.showToast(toast, in: view, duration: duration, message: message)
    }

    /// A toast that offers to take back what just happened (Undo).
    @MainActor
    @discardableResult
    public func toast(message: String, actionTitle: String, action: @escaping () -> Void) -> NSView {
        let toast = ToastFactory.makeActionToast(message: message, actionTitle: actionTitle, action: action)
        ToastManager.shared.showToast(toast, in: view, duration: ToastConfiguration.default.actionDuration)
        return toast
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

// MARK: - Undo for a move to the Trash

/// One move to the Trash and its way back. Command-Z and the toast's Undo
/// both take back this move and nothing else: the window's undo manager also
/// serves the search and title fields, so undoing whatever sits on top of it
/// could clear a search while the notes stay in the Trash.
@MainActor
final class TrashUndo {
    private var spent = false
    private weak var toast: NSView?
    private let restore: () -> Void

    private init(restore: @escaping () -> Void) {
        self.restore = restore
    }

    /// Registers the undo, and shows the Undo toast in `controller` unless it is nil.
    static func register(on undoManager: UndoManager, toastIn controller: NSViewController?, restore: @escaping () -> Void) {
        let undo = TrashUndo(restore: restore)
        // The handler holds the token: the undo manager does not retain its target.
        undoManager.registerUndo(withTarget: undo) { _ in
            MainActor.assumeIsolated { undo.takeBack() }
        }
        undoManager.setActionName(I18n.str("Move to Trash"))
        guard let controller else { return }
        undo.toast = controller.toast(message: I18n.str("Moved to Trash"), actionTitle: I18n.str("Undo")) { [weak undoManager] in
            guard !undo.spent else { return }
            undoManager?.removeAllActions(withTarget: undo)
            undo.takeBack()
        }
    }

    private func takeBack() {
        guard !spent else { return }
        spent = true
        ToastManager.shared.dismiss(toast)
        restore()
    }
}
