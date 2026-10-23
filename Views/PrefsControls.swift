import Cocoa
import KeyboardShortcuts

/// The Settings window's one row shape and three control kinds, after Mole's
/// settings: title over a one-line detail on the left, a switch, a capsule
/// dropdown or a compact pill button on the right, hairlines between rows.
@MainActor
enum PrefsMetrics {
    static let windowWidth: CGFloat = 568
    /// The unified title bar band; the tabs sit on the traffic lights' line.
    static let headerHeight: CGFloat = 52
    static let sideInset: CGFloat = 32
    static let pageTopInset: CGFloat = 4
    static let pageBottomInset: CGFloat = 20
    static let rowVerticalPadding: CGFloat = 12
    static let titleDetailSpacing: CGFloat = 2
    static let rowControlGap: CGFloat = 16
    static let controlSpacing: CGFloat = 8
    static let controlHeight: CGFloat = 24
    static let controlHorizontalPadding: CGFloat = 10
    static let pillHorizontalPadding: CGFloat = 12
    static let tabHeight: CGFloat = 28
    static let tabHorizontalPadding: CGFloat = 14
    static let shortcutWidth: CGFloat = 120
    static let fontDropdownMaxWidth: CGFloat = 196
    static let dropdownMaxWidth: CGFloat = 220

    static let titleFont = NSFont.systemFont(ofSize: 14, weight: .medium)
    static let detailFont = NSFont.systemFont(ofSize: 12)
    static let controlFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let tabFont = NSFont.systemFont(ofSize: 13, weight: .medium)
}

// MARK: - Row

@MainActor
final class PrefsRowView: NSView {
    let titleLabel: NSTextField
    let detailLabel: NSTextField
    let controlStack: NSStackView

    var detail: String {
        get { detailLabel.stringValue }
        set {
            detailLabel.stringValue = newValue
            updateDetailLayout()
        }
    }

    /// A row without a description centres its title on the control.
    private var detailConstraints: [NSLayoutConstraint] = []
    private var titleOnlyConstraints: [NSLayoutConstraint] = []

    init(title: String, detail: String, controls: [NSView], detailTruncation: NSLineBreakMode = .byTruncatingTail) {
        titleLabel = PrefsRowView.makeLabel(title, font: PrefsMetrics.titleFont, color: Theme.Settings.primaryText, truncation: .byTruncatingTail)
        detailLabel = PrefsRowView.makeLabel(detail, font: PrefsMetrics.detailFont, color: Theme.Settings.tertiaryText, truncation: detailTruncation)
        controlStack = NSStackView(views: controls)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        controlStack.translatesAutoresizingMaskIntoConstraints = false
        controlStack.orientation = .horizontal
        controlStack.alignment = .centerY
        controlStack.spacing = PrefsMetrics.controlSpacing
        controlStack.setHuggingPriority(.required, for: .horizontal)
        controlStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(controlStack)

        let padding = PrefsMetrics.rowVerticalPadding
        detailConstraints = [
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: PrefsMetrics.titleDetailSpacing),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
        ]
        titleOnlyConstraints = [
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: padding),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            controlStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: padding),
            heightAnchor.constraint(greaterThanOrEqualTo: titleLabel.heightAnchor, constant: padding * 2),
            {
                let shortest = heightAnchor.constraint(equalToConstant: 0)
                shortest.priority = .defaultLow
                return shortest
            }(),
        ]
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            controlStack.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: PrefsMetrics.rowControlGap),
            controlStack.leadingAnchor.constraint(greaterThanOrEqualTo: detailLabel.trailingAnchor, constant: PrefsMetrics.rowControlGap),
        ])
        updateDetailLayout()

        setAccessibilityElement(false)
    }

    private func updateDetailLayout() {
        let hasDetail = !detailLabel.stringValue.isEmpty
        detailLabel.isHidden = !hasDetail
        NSLayoutConstraint.deactivate(hasDetail ? titleOnlyConstraints : detailConstraints)
        NSLayoutConstraint.activate(hasDetail ? detailConstraints : titleOnlyConstraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makeLabel(_ text: String, font: NSFont, color: NSColor, truncation: NSLineBreakMode) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = font
        label.textColor = color
        label.lineBreakMode = truncation
        label.usesSingleLineMode = true
        label.maximumNumberOfLines = 1
        // The control keeps its width; a label that does not fit truncates.
        label.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }
}

/// A hairline that is one device pixel thick on any display.
@MainActor
final class PrefsHairline: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        color.setFill()
        NSRect(x: 0, y: (bounds.height - 1 / scale) / 2, width: bounds.width, height: 1 / scale).fill()
    }
}

// MARK: - Shared control chrome

@MainActor
private func drawCapsule(in rect: NSRect, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
}

@MainActor
private func drawCentredText(_ text: String, in rect: NSRect, color: NSColor, font: NSFont, alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    let lineHeight = ceil(font.ascender - font.descender)
    let textRect = NSRect(x: rect.minX, y: rect.midY - lineHeight / 2, width: rect.width, height: lineHeight)
    (text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
}

@MainActor
private func textWidth(_ text: String, font: NSFont) -> CGFloat {
    ceil((text as NSString).size(withAttributes: [.font: font]).width)
}

/// Tracks the pointer so a control can lift its fill on hover.
@MainActor
private final class HoverTracker {
    private var area: NSTrackingArea?

    func update(on view: NSView) {
        if let area { view.removeTrackingArea(area) }
        let area = NSTrackingArea(rect: view.bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: view, userInfo: nil)
        view.addTrackingArea(area)
        self.area = area
    }
}

// MARK: - Dropdown

/// A capsule dropdown: the selected value in 11pt semibold and a small
/// chevron on a 6% fill. It stays an `NSPopUpButton`, so menus, sections,
/// disabled headings and `menuNeedsUpdate` work as before; only the drawing
/// is ours.
@MainActor
final class PrefsDropdown: NSPopUpButton {
    private let hover = HoverTracker()
    private var isHovered = false {
        didSet { needsDisplay = true }
    }
    private let maximumWidth: CGFloat

    private static let chevron: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        return NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }()

    init(maximumWidth: CGFloat = PrefsMetrics.dropdownMaxWidth) {
        self.maximumWidth = maximumWidth
        super.init(frame: .zero, pullsDown: false)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        focusRingType = .exterior
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        heightAnchor.constraint(equalToConstant: PrefsMetrics.controlHeight).isActive = true
    }

    override func drawFocusRingMask() { PrefsFocusRing.capsule(in: bounds) }
    override var focusRingMaskBounds: NSRect { bounds }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Adds one item whose stored value rides on `representedObject`, so
    /// matching never depends on a localized title.
    func addOption(_ title: String, value: Any) {
        addItem(withTitle: title)
        lastItem?.representedObject = value
    }

    func selectOption(where matches: (Any?) -> Bool) {
        if let item = itemArray.first(where: { matches($0.representedObject) }) {
            select(item)
        }
    }

    private var chevronSize: NSSize { Self.chevron?.size ?? NSSize(width: 7, height: 10) }

    override var intrinsicContentSize: NSSize {
        let padding = PrefsMetrics.controlHorizontalPadding
        let width = padding + textWidth(titleOfSelectedItem ?? "", font: PrefsMetrics.controlFont) + 5 + chevronSize.width + padding
        return NSSize(width: min(ceil(width), maximumWidth), height: PrefsMetrics.controlHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: 0, y: (bounds.height - PrefsMetrics.controlHeight) / 2, width: bounds.width, height: PrefsMetrics.controlHeight)
        drawCapsule(in: rect, color: isHovered ? Theme.Settings.controlHoverFill : Theme.Settings.controlFill)

        let padding = PrefsMetrics.controlHorizontalPadding
        let chevron = chevronSize
        let chevronRect = NSRect(x: rect.maxX - padding - chevron.width, y: rect.midY - chevron.height / 2, width: chevron.width, height: chevron.height)
        if let image = Self.chevron {
            let tint = Theme.Settings.tertiaryText.resolvedColor(for: effectiveAppearance)
            let tinted = NSImage(size: chevron, flipped: false) { bounds in
                image.draw(in: bounds)
                tint.setFill()
                bounds.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: chevronRect, from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.5, respectFlipped: true, hints: nil)
        }

        let textRect = NSRect(x: rect.minX + padding, y: rect.minY, width: chevronRect.minX - 5 - rect.minX - padding, height: rect.height)
        let color = isEnabled ? Theme.Settings.secondaryText : Theme.Settings.tertiaryText
        drawCentredText(titleOfSelectedItem ?? "", in: textRect, color: color, font: PrefsMetrics.controlFont, alignment: .left)
    }

    private func selectionDidChange() {
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func synchronizeTitleAndSelectedItem() {
        super.synchronizeTitleAndSelectedItem()
        selectionDidChange()
    }

    override func select(_ item: NSMenuItem?) {
        super.select(item)
        selectionDidChange()
    }

    override func selectItem(at index: Int) {
        super.selectItem(at: index)
        selectionDidChange()
    }

    override func selectItem(withTitle title: String) {
        super.selectItem(withTitle: title)
        selectionDidChange()
    }

    override func selectItem(withTag tag: Int) -> Bool {
        defer { selectionDidChange() }
        return super.selectItem(withTag: tag)
    }

    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        selectionDidChange()
        return super.sendAction(action, to: target)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        hover.update(on: self)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }

    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - Pill button

/// The compact action button: accent text on a 12% accent capsule.
@MainActor
final class PrefsPillButton: NSButton {
    private let hover = HoverTracker()
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        focusRingType = .exterior
        setButtonType(.momentaryChange)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        heightAnchor.constraint(equalToConstant: PrefsMetrics.controlHeight).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawFocusRingMask() { PrefsFocusRing.capsule(in: bounds) }
    override var focusRingMaskBounds: NSRect { bounds }

    override var intrinsicContentSize: NSSize {
        NSSize(width: textWidth(title, font: PrefsMetrics.controlFont) + PrefsMetrics.pillHorizontalPadding * 2, height: PrefsMetrics.controlHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = Theme.Settings.accent.resolvedColor(for: effectiveAppearance)
        let pressed = isHighlighted
        let rect = NSRect(x: 0, y: (bounds.height - PrefsMetrics.controlHeight) / 2, width: bounds.width, height: PrefsMetrics.controlHeight)
        drawCapsule(in: rect, color: accent.withAlphaComponent(pressed ? 0.24 : isHovered ? 0.18 : 0.12))
        drawCentredText(title, in: rect, color: accent, font: PrefsMetrics.controlFont)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        hover.update(on: self)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }

    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - Switch

/// A small switch in MiaoYan green. `NSSwitch` only follows the system
/// accent, which would put a blue control in a green-accented window.
@MainActor
/// Keyboard focus on the capsule controls follows their own shape.
enum PrefsFocusRing {
    static func capsule(in bounds: NSRect) {
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }
}

final class PrefsSwitch: NSControl {
    private let track = CALayer()
    private let knob = CALayer()
    private static let size = NSSize(width: 30, height: 18)
    private static let knobInset: CGFloat = 2

    var isOn = false {
        didSet {
            guard oldValue != isOn else { return }
            updateLayers(animated: window != nil)
            setAccessibilityValue(isOn)
        }
    }

    init(target: AnyObject?, action: Selector?) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.addSublayer(track)
        track.addSublayer(knob)
        knob.backgroundColor = NSColor.white.cgColor
        knob.shadowColor = NSColor.black.cgColor
        knob.shadowOpacity = 0.18
        knob.shadowRadius = 1
        knob.shadowOffset = CGSize(width: 0, height: -0.5)
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityValue(false)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size.width),
            heightAnchor.constraint(equalToConstant: Self.size.height),
        ])
        updateLayers(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { Self.size }

    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { PrefsFocusRing.capsule(in: bounds) }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        updateLayers(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayers(animated: false)
    }

    override func mouseDown(with event: NSEvent) {
        toggle()
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            toggle()
        } else {
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        toggle()
        return true
    }

    private func toggle() {
        isOn.toggle()
        sendAction(action, to: target)
    }

    private func updateLayers(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.16)
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        let fill = isOn ? Theme.Settings.accent : Theme.Settings.switchOffFill
        track.frame = NSRect(x: (bounds.width - Self.size.width) / 2, y: (bounds.height - Self.size.height) / 2, width: Self.size.width, height: Self.size.height)
        track.cornerRadius = Self.size.height / 2
        track.backgroundColor = fill.resolvedColor(for: appearance).cgColor
        let diameter = Self.size.height - Self.knobInset * 2
        let x = isOn ? Self.size.width - Self.knobInset - diameter : Self.knobInset
        knob.frame = NSRect(x: x, y: Self.knobInset, width: diameter, height: diameter)
        knob.cornerRadius = diameter / 2
        CATransaction.commit()
    }
}

// MARK: - Tabs

@MainActor
final class PrefsTabBar: NSView {
    private var buttons: [PrefsTabButton] = []
    private let stack = NSStackView()
    var onSelect: ((Int) -> Void)?

    init(titles: [String]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 2
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for (index, title) in titles.enumerated() {
            let button = PrefsTabButton(title: title, target: self, action: #selector(tabClicked(_:)))
            button.tag = index
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var tabButtons: [NSButton] { buttons }

    func select(index: Int) {
        for button in buttons { button.isSelected = button.tag == index }
    }

    @objc private func tabClicked(_ sender: NSButton) {
        select(index: sender.tag)
        onSelect?(sender.tag)
    }
}

/// One tab: the selected one sits on Kami's sand, like a selected sidebar
/// row, with primary text; the others are tertiary text on the paper.
@MainActor
private final class PrefsTabButton: NSButton {
    private let hover = HoverTracker()
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    var isSelected = false {
        didSet {
            needsDisplay = true
            setAccessibilityValue(isSelected)
        }
    }

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        focusRingType = .exterior
        setButtonType(.momentaryChange)
        setAccessibilityRole(.radioButton)
        heightAnchor.constraint(equalToConstant: PrefsMetrics.tabHeight).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawFocusRingMask() { PrefsFocusRing.capsule(in: bounds) }
    override var focusRingMaskBounds: NSRect { bounds }

    override var intrinsicContentSize: NSSize {
        NSSize(width: textWidth(title, font: PrefsMetrics.tabFont) + PrefsMetrics.tabHorizontalPadding * 2, height: PrefsMetrics.tabHeight)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            drawCapsule(in: bounds, color: Theme.Settings.tabSelection)
        }
        let color: NSColor = isSelected ? Theme.Settings.primaryText : isHovered ? Theme.Settings.secondaryText : Theme.Settings.tertiaryText
        drawCentredText(title, in: bounds, color: color, font: PrefsMetrics.tabFont)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        hover.update(on: self)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }

    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - Shortcut recorder

/// KeyboardShortcuts' recorder in the dropdown's capsule, so the shortcut
/// row reads as one more value in the control column. Recording draws an
/// accent outline.
@MainActor
final class PrefsShortcutRecorder: NSView {
    private let recorder: KeyboardShortcuts.RecorderCocoa
    private var isRecording = false

    init(for name: KeyboardShortcuts.Name) {
        recorder = KeyboardShortcuts.RecorderCocoa(for: name)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = PrefsMetrics.controlHeight / 2
        layer?.borderWidth = 1
        layer?.masksToBounds = true

        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.focusRingType = .none
        recorder.isBordered = false
        recorder.isBezeled = false
        recorder.drawsBackground = false
        recorder.controlSize = .small
        recorder.font = PrefsMetrics.controlFont
        recorder.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let cell = recorder.cell as? NSSearchFieldCell {
            cell.drawsBackground = false
            cell.backgroundColor = .clear
            cell.focusRingType = .none
        }
        addSubview(recorder)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: PrefsMetrics.shortcutWidth),
            heightAnchor.constraint(equalToConstant: PrefsMetrics.controlHeight),
            recorder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            recorder.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            recorder.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(recorderActiveStatusChanged(_:)), name: .keyboardShortcutsRecorderActiveStatusDidChange, object: nil)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The whole capsule starts recording, not only the text field in it.
        guard let hit = super.hitTest(point) else { return nil }
        return hit === self ? recorder : hit
    }

    @objc private func recorderActiveStatusChanged(_ notification: Notification) {
        guard let isActive = notification.userInfo?["isActive"] as? Bool else { return }
        isRecording = isActive
        updateAppearance()
    }

    private func updateAppearance() {
        guard let layer else { return }
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        layer.backgroundColor = Theme.Settings.controlFill.resolvedColor(for: appearance).cgColor
        layer.borderColor = isRecording ? Theme.Settings.accent.resolvedColor(for: appearance).cgColor : NSColor.clear.cgColor

        let textColor = Theme.Settings.secondaryText.resolvedColor(for: appearance)
        recorder.font = PrefsMetrics.controlFont
        recorder.textColor = textColor
        if let cell = recorder.cell as? NSSearchFieldCell {
            cell.textColor = textColor
            if let placeholder = cell.placeholderString {
                cell.placeholderAttributedString = NSAttributedString(
                    string: placeholder,
                    attributes: [.foregroundColor: Theme.Settings.tertiaryText.resolvedColor(for: appearance), .font: PrefsMetrics.controlFont])
            }
        }
    }
}

extension Notification.Name {
    fileprivate static let keyboardShortcutsRecorderActiveStatusDidChange = Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange")
}
