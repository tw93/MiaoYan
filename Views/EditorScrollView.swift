import Cocoa

@MainActor
class EditorScrollView: NSScrollView {
    private var initialHeight: CGFloat?

    override var isFindBarVisible: Bool {
        get {
            super.isFindBarVisible
        }
        set {
            if let clip = subviews.first as? NSClipView {
                var currentHeight: CGFloat = 28

                for subview in subviews {
                    if subview.className.contains("FindBar") || subview.className.contains("NSFindBar") {
                        currentHeight = subview.frame.height
                        break
                    }
                }

                clip.contentInsets.top = newValue ? currentHeight : 0
                if newValue, let documentView = documentView {
                    documentView.scroll(NSPoint(x: 0, y: -currentHeight))
                }
            }

            super.isFindBarVisible = newValue

            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.removeFocusRings()
                }
            }
        }
    }

    private func removeFocusRings() {
        for subview in subviews {
            removeFocusRingsRecursively(in: subview)
        }
    }

    private func removeFocusRingsRecursively(in view: NSView) {
        view.focusRingType = .none
        if let control = view as? NSControl {
            control.focusRingType = .none
            if let cell = control.cell {
                cell.focusRingType = .none
            }
        }

        for subview in view.subviews {
            removeFocusRingsRecursively(in: subview)
        }
    }

}

// MARK: - EditorContentSplitView

@MainActor
class EditorContentSplitView: NSSplitView {

    // MARK: - Split View Constraints

    private enum SplitViewConstraints {
        static let minPaneWidth: CGFloat = 200      // Minimum width for each pane
        static let maxPaneWidth: CGFloat = 1200     // Maximum width for editor pane (for very wide displays)
        static let preferredDefaultWidth: CGFloat = 600  // Preferred default width for first use
    }

    enum DisplayMode {
        case editorOnly
        case previewOnly
        case sideBySide
    }

    private(set) var displayMode: DisplayMode = .editorOnly
    var shouldHideDivider = false
    var onResize: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isVertical = true
        dividerStyle = .thin
        autosaveName = "EditorContentSplitView"
        delegate = self
    }

    // MARK: - Mode Switching

    func setDisplayMode(_ mode: DisplayMode, animated: Bool = true) {
        displayMode = mode

        guard subviews.count == 2 else {
            return
        }

        let action = {
            switch mode {
            case .editorOnly:
                self.shouldHideDivider = true
                self.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
                self.setHoldingPriority(.defaultLow, forSubviewAt: 1)
                self.setPosition(self.bounds.width, ofDividerAt: 0)

            case .previewOnly:
                self.shouldHideDivider = true
                self.setHoldingPriority(.defaultLow, forSubviewAt: 0)
                self.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
                self.setPosition(0, ofDividerAt: 0)

            case .sideBySide:
                self.shouldHideDivider = false
                self.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
                self.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

                let savedRatio = UserDefaultsManagement.editorContentSplitPosition
                let totalWidth = max(self.bounds.width, 1)
                let clampedRatio = max(0, min(savedRatio, 1))

                var targetWidth: CGFloat

                if savedRatio > 0 {
                    // Restore saved position
                    targetWidth = totalWidth * CGFloat(clampedRatio)
                } else {
                    // First use: intelligent default
                    // Use 50% or preferredDefaultWidth, whichever is smaller
                    targetWidth = min(totalWidth * 0.5, SplitViewConstraints.preferredDefaultWidth)
                }

                // Apply constraints to ensure reasonable widths on all screen sizes
                let minWidth = SplitViewConstraints.minPaneWidth
                let maxWidth = min(totalWidth - minWidth, SplitViewConstraints.maxPaneWidth)

                // Clamp to valid range
                targetWidth = max(minWidth, min(targetWidth, maxWidth))

                self.setPosition(targetWidth, ofDividerAt: 0)
            }
            self.adjustSubviews()
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                action()
                self.layoutSubtreeIfNeeded()
            }
        } else {
            action()
            self.layoutSubtreeIfNeeded()  // Force layout update even without animation
        }
    }

    // MARK: - NSSplitView Overrides

    override var dividerColor: NSColor {
        shouldHideDivider ? .clear : super.dividerColor
    }

    override var dividerThickness: CGFloat {
        shouldHideDivider ? 0 : super.dividerThickness
    }
}

// MARK: - NSSplitViewDelegate Support

extension EditorContentSplitView: NSSplitViewDelegate {

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 && displayMode == .sideBySide {
            return SplitViewConstraints.minPaneWidth
        }
        return proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 && displayMode == .sideBySide {
            return splitView.bounds.width - SplitViewConstraints.minPaneWidth
        }
        return proposedMaximumPosition
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        if displayMode == .sideBySide, subviews.count == 2 {
            let editorWidth = subviews[0].frame.width
            let totalWidth = max(bounds.width, 1)
            let ratio = Double(editorWidth / totalWidth)
            UserDefaultsManagement.editorContentSplitPosition = ratio
        }
        onResize?()
    }
}
