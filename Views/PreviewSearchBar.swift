import Carbon.HIToolbox
import Cocoa

@MainActor
class PreviewSearchBar: NSView {
    private final class SearchField: NSSearchField {
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if handlePreviewShortcuts(event) {
                return true
            }
            return false
        }

        override func keyDown(with event: NSEvent) {
            if handlePreviewShortcuts(event) {
                return
            }
            super.keyDown(with: event)
        }

        private func handlePreviewShortcuts(_ event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else {
                return false
            }

            switch Int(event.keyCode) {
            case Int(kVK_ANSI_3):
                if NSApp.sendAction(#selector(ViewController.togglePreview(_:)), to: nil, from: self) {
                    return true
                }
                AppContext.shared.viewController?.togglePreview()
                return true
            case Int(kVK_ANSI_4):
                if NSApp.sendAction(#selector(ViewController.togglePresentation(_:)), to: nil, from: self) {
                    return true
                }
                AppContext.shared.viewController?.togglePresentation()
                return true
            default:
                return false
            }
        }
    }

    enum Mode {
        case find
        case replace
    }

    private let searchField = SearchField()
    private let replaceField = NSSearchField()
    private let matchLabel = NSTextField()
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let replaceButton = NSButton()
    private let replaceAllButton = NSButton()
    private let doneButton = NSButton()
    private var panelBaseColor: NSColor = Theme.backgroundColor

    private var currentMatchIndex: Int = 0
    private var totalMatches: Int = 0
    private var mode: Mode = .find

    var onSearch: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onReplace: ((String) -> Void)?
    var onReplaceAll: ((String) -> Void)?
    var onClose: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        autoresizingMask = []
        wantsLayer = true
        applyCornerMask()
        layer?.borderWidth = 0
        layer?.borderColor = nil
        updatePanelBackground()

        searchField.placeholderString = I18n.str("Search")
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType = .none
        searchField.delegate = self
        if let cell = searchField.cell as? NSSearchFieldCell {
            cell.focusRingType = .none
            cell.searchButtonCell = nil
            cell.cancelButtonCell = nil
        }
        addSubview(searchField)

        replaceField.placeholderString = I18n.str("Replace")
        replaceField.font = NSFont.systemFont(ofSize: 13)
        replaceField.translatesAutoresizingMaskIntoConstraints = false
        replaceField.focusRingType = .none
        if let cell = replaceField.cell as? NSSearchFieldCell {
            cell.focusRingType = .none
            cell.searchButtonCell = nil
            cell.cancelButtonCell = nil
        }
        addSubview(replaceField)

        matchLabel.isEditable = false
        matchLabel.isBordered = false
        matchLabel.drawsBackground = false
        matchLabel.font = NSFont.systemFont(ofSize: 11)
        matchLabel.textColor = .secondaryLabelColor
        matchLabel.alignment = .center
        matchLabel.stringValue = ""
        matchLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(matchLabel)

        previousButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: I18n.str("Previous"))
        previousButton.bezelStyle = .shadowlessSquare
        previousButton.isBordered = false
        previousButton.target = self
        previousButton.action = #selector(previousClicked)
        previousButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previousButton)

        nextButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: I18n.str("Next"))
        nextButton.bezelStyle = .shadowlessSquare
        nextButton.isBordered = false
        nextButton.target = self
        nextButton.action = #selector(nextClicked)
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nextButton)

        replaceButton.image = createReplaceIcon()
        replaceButton.bezelStyle = .shadowlessSquare
        replaceButton.isBordered = false
        replaceButton.target = self
        replaceButton.action = #selector(replaceClicked)
        replaceButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(replaceButton)

        replaceAllButton.image = createReplaceAllIcon()
        replaceAllButton.bezelStyle = .shadowlessSquare
        replaceAllButton.isBordered = false
        replaceAllButton.target = self
        replaceAllButton.action = #selector(replaceAllClicked)
        replaceAllButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(replaceAllButton)

        doneButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: I18n.str("Done"))
        doneButton.bezelStyle = .shadowlessSquare
        doneButton.isBordered = false
        doneButton.target = self
        doneButton.action = #selector(doneClicked)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(doneButton)

        replaceField.isHidden = true
        replaceButton.isHidden = true
        replaceAllButton.isHidden = true

        setupConstraints()
    }

    private var searchFieldTopConstraint: NSLayoutConstraint!
    private var buttonGroupLeading: CGFloat = 250

    private func setupConstraints() {
        searchFieldTopConstraint = searchField.topAnchor.constraint(equalTo: topAnchor, constant: 8)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchFieldTopConstraint,
            searchField.widthAnchor.constraint(equalToConstant: 180),

            matchLabel.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 6),
            matchLabel.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            matchLabel.widthAnchor.constraint(equalToConstant: 50),

            previousButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonGroupLeading),
            previousButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 28),
            previousButton.heightAnchor.constraint(equalToConstant: 22),

            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 2),
            nextButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 28),
            nextButton.heightAnchor.constraint(equalToConstant: 22),

            doneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            doneButton.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            doneButton.widthAnchor.constraint(equalToConstant: 28),
            doneButton.heightAnchor.constraint(equalToConstant: 22),

            replaceField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            replaceField.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            replaceField.widthAnchor.constraint(equalToConstant: 180),

            replaceButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: buttonGroupLeading),
            replaceButton.centerYAnchor.constraint(equalTo: replaceField.centerYAnchor),
            replaceButton.widthAnchor.constraint(equalToConstant: 28),
            replaceButton.heightAnchor.constraint(equalToConstant: 22),

            replaceAllButton.leadingAnchor.constraint(equalTo: replaceButton.trailingAnchor, constant: 2),
            replaceAllButton.centerYAnchor.constraint(equalTo: replaceField.centerYAnchor),
            replaceAllButton.widthAnchor.constraint(equalToConstant: 28),
            replaceAllButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @objc private func searchFieldChanged() {
        let searchText = searchField.stringValue
        onSearch?(searchText)
    }

    @objc private func previousClicked() {
        onPrevious?()
    }

    @objc private func nextClicked() {
        onNext?()
    }

    @objc private func replaceClicked() {
        let replaceText = replaceField.stringValue
        onReplace?(replaceText)
    }

    @objc private func replaceAllClicked() {
        let replaceText = replaceField.stringValue
        onReplaceAll?(replaceText)
    }

    @objc private func doneClicked() {
        onClose?()
    }

    func updateMatchInfo(current: Int, total: Int) {
        currentMatchIndex = current
        totalMatches = total

        if total > 0 {
            matchLabel.stringValue = "\(current)/\(total)"
            matchLabel.textColor = .labelColor
        } else if !searchField.stringValue.isEmpty {
            matchLabel.stringValue = "0/0"
            matchLabel.textColor = Theme.linkColor
        } else {
            matchLabel.stringValue = ""
        }

        previousButton.isEnabled = total > 0
        nextButton.isEnabled = total > 0
        replaceButton.isEnabled = total > 0
        replaceAllButton.isEnabled = total > 0
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
        let isReplaceMode = (mode == .replace)
        replaceField.isHidden = !isReplaceMode
        replaceButton.isHidden = !isReplaceMode
        replaceAllButton.isHidden = !isReplaceMode

        if isReplaceMode {
            searchFieldTopConstraint.constant = 11
        } else {
            searchFieldTopConstraint.constant = 8
        }
    }

    private func clearSearchField() {
        if let editor = searchField.currentEditor() {
            editor.selectAll(nil)
            editor.delete(nil)
        }
        searchField.stringValue = ""
        onSearch?("")
    }

    func focusSearchField(selectAll: Bool = false) {
        window?.makeFirstResponder(searchField)
        if selectAll, let editor = searchField.currentEditor() {
            DispatchQueue.main.async {
                editor.selectAll(nil)
            }
        }
    }

    func setSearchText(_ text: String, selectAll: Bool = true) {
        searchField.stringValue = text
        if selectAll {
            window?.makeFirstResponder(searchField)
            if let editor = searchField.currentEditor() {
                editor.selectAll(nil)
            }
        }
    }

    func configureAppearance(baseColor: NSColor) {
        panelBaseColor = baseColor
        updatePanelBackground()
    }

    var searchText: String {
        searchField.stringValue
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == kVK_Delete,
            flags.contains(.command),
            !flags.contains(.option),
            !flags.contains(.control)
        {
            clearSearchField()
            return true
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onClose?()
        } else if event.keyCode == 36 {
            if event.modifierFlags.contains(.shift) {
                onPrevious?()
            } else {
                onNext?()
            }
        } else {
            super.keyDown(with: event)
        }
    }
}

extension PreviewSearchBar: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        let searchText = searchField.stringValue
        onSearch?(searchText)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        case #selector(NSText.deleteToBeginningOfLine(_:)),
            #selector(NSText.deleteToBeginningOfParagraph(_:)):
            clearSearchField()
            return true
        case #selector(NSResponder.insertNewline(_:)),
            #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                onPrevious?()
            } else {
                onNext?()
            }
            return true
        default:
            return false
        }
    }
}

extension PreviewSearchBar {
    fileprivate static func panelBackgroundColor(base: NSColor) -> NSColor {
        guard let rgb = base.usingColorSpace(.sRGB) else {
            return base
        }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        if luminance < 0.5 {
            // Dark mode: deepen the tone slightly for clearer separation
            return (rgb.shadow(withLevel: 0.18) ?? rgb)
        } else {
            // Light mode: add subtle depth so the bar stays visible
            return (rgb.shadow(withLevel: 0.08) ?? rgb)
        }
    }

    fileprivate func updatePanelBackground() {
        guard wantsLayer else { return }
        let panelColor = PreviewSearchBar.panelBackgroundColor(base: panelBaseColor)
        layer?.backgroundColor = panelColor.cgColor

        updateShadowAppearance(for: panelColor)
        applyCornerMask()
    }

    fileprivate func updateShadowAppearance(for color: NSColor) {
        guard wantsLayer, let rgb = color.usingColorSpace(.sRGB) else { return }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        if luminance < 0.5 {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.45
            layer?.shadowRadius = 12
            layer?.shadowOffset = NSSize(width: 0, height: -4)
        } else {
            layer?.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
            layer?.shadowOpacity = 0.35
            layer?.shadowRadius = 9
            layer?.shadowOffset = NSSize(width: 0, height: -2.5)
        }
    }

    fileprivate func applyCornerMask() {
        guard wantsLayer else { return }
        if #available(macOS 10.13, *) {
            layer?.cornerRadius = 8
            layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            layer?.masksToBounds = true
            layer?.mask = nil
        } else {
            let maskLayer = CAShapeLayer()
            maskLayer.frame = bounds
            maskLayer.path = leftRoundedCornerPath(radius: 8).cgPath
            layer?.mask = maskLayer
        }
    }

    fileprivate func leftRoundedCornerPath(radius: CGFloat) -> NSBezierPath {
        let rect = bounds
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        let path = NSBezierPath()
        path.move(to: NSPoint(x: maxX, y: maxY))
        path.line(to: NSPoint(x: minX + radius, y: maxY))
        path.appendArc(withCenter: NSPoint(x: minX + radius, y: maxY - radius), radius: radius, startAngle: 90, endAngle: 180, clockwise: true)
        path.line(to: NSPoint(x: minX, y: minY + radius))
        path.appendArc(withCenter: NSPoint(x: minX + radius, y: minY + radius), radius: radius, startAngle: 180, endAngle: 270, clockwise: true)
        path.line(to: NSPoint(x: maxX, y: minY))
        path.close()
        return path
    }

    private func createReplaceIcon() -> NSImage? {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.isTemplate = true

        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let path = NSBezierPath()
        let scale: CGFloat = 16.0 / 24.0

        path.move(to: NSPoint(x: 14 * scale, y: (24 - 4) * scale))
        path.curve(
            to: NSPoint(x: 15 * scale, y: (24 - 3) * scale),
            controlPoint1: NSPoint(x: 14.552 * scale, y: (24 - 4) * scale),
            controlPoint2: NSPoint(x: 15 * scale, y: (24 - 3.552) * scale))

        path.move(to: NSPoint(x: 15 * scale, y: (24 - 10) * scale))
        path.curve(
            to: NSPoint(x: 14 * scale, y: (24 - 9) * scale),
            controlPoint1: NSPoint(x: 15 * scale, y: (24 - 9.448) * scale),
            controlPoint2: NSPoint(x: 14.552 * scale, y: (24 - 9) * scale))

        path.move(to: NSPoint(x: 21 * scale, y: (24 - 4) * scale))
        path.curve(
            to: NSPoint(x: 20 * scale, y: (24 - 3) * scale),
            controlPoint1: NSPoint(x: 21 * scale, y: (24 - 3.448) * scale),
            controlPoint2: NSPoint(x: 20.552 * scale, y: (24 - 3) * scale))

        path.move(to: NSPoint(x: 21 * scale, y: (24 - 9) * scale))
        path.curve(
            to: NSPoint(x: 20 * scale, y: (24 - 10) * scale),
            controlPoint1: NSPoint(x: 21 * scale, y: (24 - 9.552) * scale),
            controlPoint2: NSPoint(x: 20.552 * scale, y: (24 - 10) * scale))

        path.move(to: NSPoint(x: 3 * scale, y: (24 - 7) * scale))
        path.line(to: NSPoint(x: 6 * scale, y: (24 - 10) * scale))
        path.line(to: NSPoint(x: 9 * scale, y: (24 - 7) * scale))

        path.move(to: NSPoint(x: 6 * scale, y: (24 - 10) * scale))
        path.line(to: NSPoint(x: 6 * scale, y: (24 - 5) * scale))
        path.curve(
            to: NSPoint(x: 8 * scale, y: (24 - 3) * scale),
            controlPoint1: NSPoint(x: 6 * scale, y: (24 - 3.895) * scale),
            controlPoint2: NSPoint(x: 6.895 * scale, y: (24 - 3) * scale))
        path.line(to: NSPoint(x: 10 * scale, y: (24 - 3) * scale))

        path.appendRoundedRect(
            NSRect(x: 3 * scale, y: (24 - 21) * scale, width: 7 * scale, height: 7 * scale),
            xRadius: 1 * scale, yRadius: 1 * scale)

        NSColor.black.setStroke()
        path.lineWidth = 1.0
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()

        image.unlockFocus()
        return image
    }

    private func createReplaceAllIcon() -> NSImage? {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.isTemplate = true

        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let path = NSBezierPath()
        let scale: CGFloat = 16.0 / 24.0

        path.move(to: NSPoint(x: 14 * scale, y: (24 - 14) * scale))
        path.curve(
            to: NSPoint(x: 15 * scale, y: (24 - 15) * scale),
            controlPoint1: NSPoint(x: 14.552 * scale, y: (24 - 14) * scale),
            controlPoint2: NSPoint(x: 15 * scale, y: (24 - 14.448) * scale))
        path.line(to: NSPoint(x: 15 * scale, y: (24 - 20) * scale))
        path.curve(
            to: NSPoint(x: 14 * scale, y: (24 - 21) * scale),
            controlPoint1: NSPoint(x: 15 * scale, y: (24 - 20.552) * scale),
            controlPoint2: NSPoint(x: 14.552 * scale, y: (24 - 21) * scale))

        path.move(to: NSPoint(x: 14 * scale, y: (24 - 4) * scale))
        path.curve(
            to: NSPoint(x: 15 * scale, y: (24 - 3) * scale),
            controlPoint1: NSPoint(x: 14.552 * scale, y: (24 - 4) * scale),
            controlPoint2: NSPoint(x: 15 * scale, y: (24 - 3.552) * scale))

        path.move(to: NSPoint(x: 15 * scale, y: (24 - 10) * scale))
        path.curve(
            to: NSPoint(x: 14 * scale, y: (24 - 9) * scale),
            controlPoint1: NSPoint(x: 15 * scale, y: (24 - 9.448) * scale),
            controlPoint2: NSPoint(x: 14.552 * scale, y: (24 - 9) * scale))

        path.move(to: NSPoint(x: 19 * scale, y: (24 - 14) * scale))
        path.curve(
            to: NSPoint(x: 20 * scale, y: (24 - 15) * scale),
            controlPoint1: NSPoint(x: 19.552 * scale, y: (24 - 14) * scale),
            controlPoint2: NSPoint(x: 20 * scale, y: (24 - 14.448) * scale))
        path.line(to: NSPoint(x: 20 * scale, y: (24 - 20) * scale))
        path.curve(
            to: NSPoint(x: 19 * scale, y: (24 - 21) * scale),
            controlPoint1: NSPoint(x: 20 * scale, y: (24 - 20.552) * scale),
            controlPoint2: NSPoint(x: 19.552 * scale, y: (24 - 21) * scale))

        path.move(to: NSPoint(x: 21 * scale, y: (24 - 4) * scale))
        path.curve(
            to: NSPoint(x: 20 * scale, y: (24 - 3) * scale),
            controlPoint1: NSPoint(x: 21 * scale, y: (24 - 3.448) * scale),
            controlPoint2: NSPoint(x: 20.552 * scale, y: (24 - 3) * scale))

        path.move(to: NSPoint(x: 21 * scale, y: (24 - 9) * scale))
        path.curve(
            to: NSPoint(x: 20 * scale, y: (24 - 10) * scale),
            controlPoint1: NSPoint(x: 21 * scale, y: (24 - 9.552) * scale),
            controlPoint2: NSPoint(x: 20.552 * scale, y: (24 - 10) * scale))

        path.move(to: NSPoint(x: 3 * scale, y: (24 - 7) * scale))
        path.line(to: NSPoint(x: 6 * scale, y: (24 - 10) * scale))
        path.line(to: NSPoint(x: 9 * scale, y: (24 - 7) * scale))

        path.move(to: NSPoint(x: 6 * scale, y: (24 - 10) * scale))
        path.line(to: NSPoint(x: 6 * scale, y: (24 - 5) * scale))
        path.curve(
            to: NSPoint(x: 8 * scale, y: (24 - 3) * scale),
            controlPoint1: NSPoint(x: 6 * scale, y: (24 - 3.895) * scale),
            controlPoint2: NSPoint(x: 6.895 * scale, y: (24 - 3) * scale))
        path.line(to: NSPoint(x: 10 * scale, y: (24 - 3) * scale))

        path.appendRoundedRect(
            NSRect(x: 3 * scale, y: (24 - 21) * scale, width: 7 * scale, height: 7 * scale),
            xRadius: 1 * scale, yRadius: 1 * scale)

        NSColor.black.setStroke()
        path.lineWidth = 1.0
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()

        image.unlockFocus()
        return image
    }
}

extension NSBezierPath {
    fileprivate var cgPath: CGPath {
        let path = CGMutablePath()
        let points = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
        defer { points.deallocate() }
        for index in 0..<elementCount {
            let type = element(at: index, associatedPoints: points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            default:
                break
            }
        }
        return path
    }
}

extension PreviewSearchBar {
    override func layout() {
        super.layout()
        applyCornerMask()
    }
}
