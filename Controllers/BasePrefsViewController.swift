import Cocoa

@MainActor
enum PrefsFormMetrics {
    static let pageInsets = NSEdgeInsets(top: 72, left: 28, bottom: 24, right: 28)
    static let rowSpacing: CGFloat = 14
    static let groupSpacing: CGFloat = 20
    static let labelWidth: CGFloat = 164
    static let controlSpacing: CGFloat = 16
    static let rowHeight: CGFloat = 30
    static let controlWidth: CGFloat = 220
    static let compactControlWidth: CGFloat = 96
}

@MainActor
class BasePrefsViewController: NSViewController {
    private weak var preferencesStackView: NSStackView?

    override func loadView() {
        setupBaseView()
        setupUI()
        // Size the stack to its content right after the rows are added. The
        // stack is frame-based (translatesAutoresizingMaskIntoConstraints), so
        // a leftover zero frame makes AppKit synthesize width==0 / height==0
        // autoresizing constraints that fight the rows' intrinsic widths and
        // flood the console with "Unable to simultaneously satisfy constraints"
        // on the first layout pass.
        layoutPreferencesStack()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupValues()
    }

    override func viewWillLayout() {
        super.viewWillLayout()
        // Set the frame before the layout pass evaluates constraints, not after
        // (viewDidLayout is one pass too late to prevent the transient conflict).
        layoutPreferencesStack()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutPreferencesStack()
    }

    private func setupBaseView() {
        view = PrefsBackgroundView()
    }

    // MARK: - Hooks for subclasses
    @objc func setupUI() {}
    @objc func setupValues() {}

    func installPreferencesStack() -> NSStackView {
        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = true
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.spacing = PrefsFormMetrics.rowSpacing
        stackView.setContentHuggingPriority(.required, for: .vertical)
        stackView.setContentCompressionResistancePriority(.required, for: .vertical)
        view.addSubview(stackView)
        preferencesStackView = stackView

        return stackView
    }

    private func layoutPreferencesStack() {
        guard let stackView = preferencesStackView else { return }

        let insets = PrefsFormMetrics.pageInsets
        let fittingSize = stackView.fittingSize
        // Always give the form its content width (the rows hard-require >=420).
        // Clamping to the view's current width clipped the stack narrower than
        // its rows during early layout passes (e.g. a 323pt transient bounds),
        // which is what produced the constraint conflicts. The form is
        // left-aligned at a fixed width; extra window width is just trailing
        // space, so there is nothing to clamp against.
        let width = max(fittingSize.width, 420)

        stackView.frame = NSRect(
            x: insets.left,
            y: insets.top,
            width: width,
            height: fittingSize.height
        )
    }

    func makePreferencesRow(labelText: String, control: NSView, controlWidth: CGFloat? = PrefsFormMetrics.controlWidth) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: labelText)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .right
        label.font = .systemFont(ofSize: 13)
        label.textColor = Theme.secondaryTextColor
        label.lineBreakMode = .byTruncatingTail

        control.translatesAutoresizingMaskIntoConstraints = false
        configurePreferencesControl(control)

        rowView.addSubview(label)
        rowView.addSubview(control)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: PrefsFormMetrics.labelWidth),

            control.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: PrefsFormMetrics.controlSpacing),
            control.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            rowView.trailingAnchor.constraint(greaterThanOrEqualTo: control.trailingAnchor),
            rowView.heightAnchor.constraint(greaterThanOrEqualToConstant: PrefsFormMetrics.rowHeight),
        ])

        if let controlWidth {
            let width = control.widthAnchor.constraint(equalToConstant: controlWidth)
            width.priority = .defaultHigh
            width.isActive = true
        }

        return rowView
    }

    func makePreferencesSeparator() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let line = PrefsHairlineView()
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)

        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: PrefsFormMetrics.labelWidth + PrefsFormMetrics.controlSpacing),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])

        container.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true
        return container
    }

    func makeControlStack(_ views: [NSView], spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    func configurePreferencesControl(_ view: NSView) {
        Theme.configureModernControlMetrics(view)
        if let control = view as? NSControl {
            control.controlSize = .regular
        }
        for subview in view.subviews {
            configurePreferencesControl(subview)
        }
    }

    func makeSegmentedControl(labels: [String], action: Selector) -> PrefsSegmentedControl {
        let control = PrefsSegmentedControl(labels: labels, target: self, action: action)
        control.translatesAutoresizingMaskIntoConstraints = false
        configurePreferencesControl(control)
        return control
    }

    func showRestartAlert(completion: ((Bool) -> Void)? = nil) {
        guard let window = view.window else {
            completion?(false)
            return
        }

        MiaoYanAlert.confirm(
            message: I18n.str("Restart to MiaoYan to take effect"),
            confirmTitle: I18n.str("Confirm"),
            style: .informational,
            for: window
        ) { confirmed in
            if confirmed {
                UserDefaultsManagement.isFirstLaunch = true
                DispatchQueue.main.asyncAfter(deadline: .now() + UIDelay.short) {
                    AppDelegate.relaunchApp()
                }
            }
            completion?(confirmed)
        }
    }
}

private final class PrefsBackgroundView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        updateColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        let resolvedColor = Theme.settingsContentBackgroundColor.resolvedColor(for: appearance)
        layer?.backgroundColor = resolvedColor.cgColor
    }
}

private final class PrefsHairlineView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    private func commonInit() {
        wantsLayer = true
        updateColor()
    }

    private func updateColor() {
        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        layer?.backgroundColor = Theme.settingsDividerColor.resolvedColor(for: appearance).cgColor
    }
}

@MainActor
final class PrefsSegmentedControl: NSControl {
    private let labels: [String]
    private let controlHeight: CGFloat = 28

    var selectedSegment: Int = 0 {
        didSet {
            selectedSegment = max(0, min(selectedSegment, labels.count - 1))
            needsDisplay = true
        }
    }

    init(labels: [String], target: AnyObject?, action: Selector?) {
        self.labels = labels
        super.init(frame: .zero)
        self.target = target
        self.action = action
        commonInit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let labelWidths = labels.reduce(CGFloat(0)) { partial, label in
            let width = (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
            return partial + ceil(width) + 34
        }
        return NSSize(width: max(PrefsFormMetrics.controlWidth, labelWidths), height: controlHeight)
    }

    override var acceptsFirstResponder: Bool { true }

    func label(forSegment segment: Int) -> String? {
        guard labels.indices.contains(segment) else { return nil }
        return labels[segment]
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !labels.isEmpty else { return }

        let appearance = window?.effectiveAppearance ?? effectiveAppearance
        let trackRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: 7, yRadius: 7)
        trackColor(for: appearance).setFill()
        trackPath.fill()

        Theme.panelHairlineColor.resolvedColor(for: appearance).setStroke()
        trackPath.lineWidth = 1 / (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        trackPath.stroke()

        let segmentWidth = bounds.width / CGFloat(labels.count)
        let selectedRect = NSRect(
            x: bounds.minX + CGFloat(selectedSegment) * segmentWidth + 1,
            y: bounds.minY + 1,
            width: segmentWidth - 2,
            height: bounds.height - 2
        )
        let selectedPath = NSBezierPath(roundedRect: selectedRect, xRadius: 6, yRadius: 6)
        Theme.selectionBackgroundColor.resolvedColor(for: appearance).setFill()
        selectedPath.fill()

        let strokeWidth = 1 / (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        let selectedStrokeRect = selectedRect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
        let selectedStrokePath = NSBezierPath(roundedRect: selectedStrokeRect, xRadius: 6, yRadius: 6)
        selectedStrokePath.lineWidth = strokeWidth
        Theme.sidebarSelectionStrokeColor.resolvedColor(for: appearance).setStroke()
        selectedStrokePath.stroke()

        drawLabels(segmentWidth: segmentWidth, appearance: appearance)
    }

    override func mouseDown(with event: NSEvent) {
        guard !labels.isEmpty else { return }
        updateSelection(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:  // Left arrow
            setSelectedSegment(selectedSegment - 1, sendAction: true)
        case 124:  // Right arrow
            setSelectedSegment(selectedSegment + 1, sendAction: true)
        case 36, 49:  // Return, Space
            sendAction(action, to: target)
        default:
            super.keyDown(with: event)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func commonInit() {
        wantsLayer = true
        focusRingType = .none
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        heightAnchor.constraint(equalToConstant: controlHeight).isActive = true
    }

    private func updateSelection(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        let segmentWidth = bounds.width / CGFloat(labels.count)
        let index = Int(point.x / segmentWidth)
        setSelectedSegment(index, sendAction: true)
    }

    private func setSelectedSegment(_ segment: Int, sendAction shouldSendAction: Bool) {
        let clamped = max(0, min(segment, labels.count - 1))
        guard clamped != selectedSegment || shouldSendAction else { return }
        selectedSegment = clamped
        if shouldSendAction {
            sendAction(action, to: target)
        }
    }

    private func trackColor(for appearance: NSAppearance?) -> NSColor {
        let isDark = appearance?.isDark ?? false
        if isDark {
            return NSColor.white.withAlphaComponent(0.07)
        }
        return NSColor.black.withAlphaComponent(0.06)
    }

    private func drawLabels(segmentWidth: CGFloat, appearance: NSAppearance?) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        for (index, label) in labels.enumerated() {
            let isSelected = index == selectedSegment
            let rect = NSRect(
                x: bounds.minX + CGFloat(index) * segmentWidth + 8,
                y: bounds.midY - 8,
                width: segmentWidth - 16,
                height: 17
            )
            let color = (isSelected ? Theme.textColor : Theme.secondaryTextColor).resolvedColor(for: appearance)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .medium : .regular),
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
            (label as NSString).draw(in: rect, withAttributes: attributes)
        }
    }
}
