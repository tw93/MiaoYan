import Cocoa

// MARK: - Layout Management
extension ViewController {

    // MARK: - Layout Constants
    private enum LayoutConstants {
        static let minSidebarWidth: CGFloat = 138
        static let maxSidebarWidth: CGFloat = 280
        static let defaultNotelistWidth: CGFloat = 280
        static let narrowThreshold: CGFloat = 50
        static let searchTopSidebarCollapsed: CGFloat = 30.0
        static let searchTopNormal: CGFloat = 13.0
        static let titlebarHeightNarrow: CGFloat = 54.0
        static let titlebarHeightEditorOnly: CGFloat = 66.0
        static let titlebarHeightNormal: CGFloat = 52.0
        static let titleTopNarrow: CGFloat = 22.0
        static let titleTopEditorOnly: CGFloat = 32.0
        static let titleTopNormal: CGFloat = 16.0
        static let titleLeadingNormal: CGFloat = 25.0
        static let titleLeadingEditorOnly: CGFloat = 30.0
        static let titleBarActionsTopNormal: CGFloat = 18.0
        static let titleBarActionsTopEditorOnly: CGFloat = 28.0
    }

    // MARK: - Properties
    var sidebarWidth: CGFloat {
        guard let splitView = sidebarSplitView,
            !splitView.subviews.isEmpty
        else { return 0 }
        return splitView.subviews[0].frame.width
    }

    var notelistWidth: CGFloat {
        guard !splitView.subviews.isEmpty else { return 0 }
        return splitView.subviews[0].frame.width
    }

    private var isSidebarVisible: Bool {
        guard let sidebarView = sidebarSplitView?.subviews.first else { return false }
        return !sidebarView.isHidden && sidebarWidth > Theme.Metrics.collapsedSplitWidthEpsilon
    }

    private var isNotelistVisible: Bool {
        guard let noteListView = splitView?.subviews.first else { return false }
        return !noteListView.isHidden && notelistWidth > Theme.Metrics.collapsedSplitWidthEpsilon
    }

    // MARK: - Layout Management Methods
    func checkSidebarConstraint() {
        let isSidebarCollapsed = !isSidebarVisible && !UserDefaultsManagement.isWillFullScreen
        searchTopConstraint.constant = isSidebarCollapsed ? LayoutConstants.searchTopSidebarCollapsed : LayoutConstants.searchTopNormal
    }

    func checkTitlebarTopConstraint() {
        let isNarrow = !isNotelistVisible && !UserDefaultsManagement.isWillFullScreen
        let isEditorOnly = isNarrow && !isSidebarVisible

        if isEditorOnly {
            titiebarHeight.constant = LayoutConstants.titlebarHeightEditorOnly
            titleTopConstraint.constant = LayoutConstants.titleTopEditorOnly
        } else {
            titiebarHeight.constant = isNarrow ? LayoutConstants.titlebarHeightNarrow : LayoutConstants.titlebarHeightNormal
            titleTopConstraint.constant = isNarrow ? LayoutConstants.titleTopNarrow : LayoutConstants.titleTopNormal
        }

        updateTitleLeadingInset(isEditorOnly ? LayoutConstants.titleLeadingEditorOnly : LayoutConstants.titleLeadingNormal)
        updateTitleBarActionsTop(isEditorOnly ? LayoutConstants.titleBarActionsTopEditorOnly : LayoutConstants.titleBarActionsTopNormal)
    }

    private func updateTitleLeadingInset(_ inset: CGFloat) {
        guard let titleLabel, let container = titleLabel.superview else { return }
        for constraint in container.constraints where constraint.firstItem === titleLabel && constraint.firstAttribute == .leading {
            constraint.constant = inset
        }
    }

    private func updateTitleBarActionsTop(_ top: CGFloat) {
        guard let titleBarAdditionalView, let formatButton else { return }

        for constraint in titleBarAdditionalView.constraints {
            let first = constraint.firstItem as? NSView
            let second = constraint.secondItem as? NSView
            guard constraint.firstAttribute == .top,
                constraint.secondAttribute == .top
            else { continue }

            if first === formatButton && second === titleBarAdditionalView {
                constraint.constant = top
            } else if first === titleBarAdditionalView && second === formatButton {
                constraint.constant = -top
            }
        }
    }

    // MARK: - Core Panel Operations

    private var isPresentationMode: Bool {
        sessionPresentationMode || sessionMagicPPTMode
    }

    func setSidebarVisible(_ visible: Bool, saveState: Bool = true) {
        let sidebarView = sidebarSplitView.subviews.first
        if visible {
            sidebarView?.isHidden = false
            let savedWidth = UserDefaultsManagement.realSidebarSize
            let targetWidth = max(savedWidth, Int(LayoutConstants.minSidebarWidth))

            if savedWidth < Int(LayoutConstants.minSidebarWidth) {
                UserDefaultsManagement.realSidebarSize = Int(LayoutConstants.minSidebarWidth)
            }

            sidebarSplitView.setPosition(CGFloat(targetWidth), ofDividerAt: 0)
        } else {
            if saveState && !isPresentationMode && sidebarWidth > Theme.Metrics.sidebarCollapseSnapWidth {
                UserDefaultsManagement.realSidebarSize = Int(sidebarWidth)
            }
            sidebarSplitView.setPosition(0, ofDividerAt: 0)
            sidebarView?.isHidden = true
        }
        editArea.updateTextContainerInset()
        sidebarSplitView?.layoutSubtreeIfNeeded()
        (sidebarSplitView as? ThemedSplitView)?.applyDividerColor()
        updateSidebarColumnWidth()
        checkSidebarConstraint()
        updateToolbarButtonTints()
    }

    func ensurePanelsVisibleAtStartup() {
        guard !UserDefaultsManagement.isSingleMode else { return }
        let shouldShowSidebar = isSidebarVisible
        let shouldShowNotelist = isNotelistVisible

        if shouldShowSidebar && !shouldShowNotelist {
            showNoteList("")
        }

        normalizeNotelistWidth(saveState: false)
    }

    private func setNotelistVisible(_ visible: Bool, saveState: Bool = true) {
        let noteListView = splitView.subviews.first
        if visible {
            noteListView?.isHidden = false
            let savedWidth = UserDefaultsManagement.sidebarSize
            let fallbackWidth = Int(LayoutConstants.defaultNotelistWidth)
            let targetWidth = max(savedWidth > 0 ? savedWidth : fallbackWidth, Int(Theme.Metrics.noteListMinimumWidth))
            splitView.shouldHideDivider = false
            splitView.setPosition(CGFloat(targetWidth), ofDividerAt: 0)

            // Sync selection: If editor has a note, select it in the list (suppressing side effects like reloading)
            if let currentNote = EditTextView.note {
                if let index = notesTableView.getIndex(currentNote) {
                    notesTableView.selectRow(index, ensureVisible: true, suppressSideEffects: true)
                }
            }
        } else {
            if saveState && !isPresentationMode && notelistWidth >= Theme.Metrics.noteListMinimumWidth {
                UserDefaultsManagement.sidebarSize = Int(notelistWidth)
            }
            splitView.shouldHideDivider = true
            splitView.setPosition(0, ofDividerAt: 0)
            noteListView?.isHidden = true
        }
        editArea.updateTextContainerInset()
        splitView.layoutSubtreeIfNeeded()
        splitView.applyDividerColor()
        checkTitlebarTopConstraint()
        updateToolbarButtonTints()
    }

    private func normalizeNotelistWidth(saveState: Bool) {
        let width = notelistWidth
        guard !isNormalizingNotelistWidth,
            isNotelistVisible,
            width < Theme.Metrics.noteListMinimumWidth
        else { return }

        isNormalizingNotelistWidth = true
        defer { isNormalizingNotelistWidth = false }
        if width < Theme.Metrics.noteListCollapseSnapWidth {
            collapseNotelist(saveState: saveState)
        } else {
            setNotelistVisible(true, saveState: saveState)
        }
    }

    private func collapseNotelist(saveState: Bool = true) {
        setNotelistVisible(false, saveState: saveState)
        if isSidebarVisible {
            setSidebarVisible(false, saveState: saveState)
        }
    }

    // MARK: - Sidebar Management

    func hideSidebar(_ sender: Any) {
        guard isSidebarVisible else { return }

        // 隐藏 sidebar → 不影响 notelist（允许两栏模式）
        setSidebarVisible(false)
    }

    func showSidebar(_ sender: Any) {
        guard !isSidebarVisible else { return }

        // 显示 sidebar → 自动显示 notelist
        if !isNotelistVisible {
            setNotelistVisible(true)
        }
        setSidebarVisible(true)
    }

    // MARK: - Note List Management

    func showNoteList(_ sender: Any) {
        guard !isNotelistVisible else { return }

        // 显示 notelist → 不强制显示 sidebar（允许两栏模式）
        setNotelistVisible(true)
    }

    func hideNoteList(_ sender: Any) {
        guard isNotelistVisible else { return }

        // 隐藏 notelist → 自动隐藏 sidebar
        collapseNotelist()
    }

    // MARK: - Toggle Actions
    @IBAction func toggleNoteList(_ sender: Any) {
        guard splitView != nil else { return }
        isNotelistVisible ? hideNoteList(sender) : showNoteList(sender)
    }

    @IBAction func toggleLayoutCycle(_ sender: Any) {
        guard splitView != nil, sidebarSplitView != nil else { return }

        // 1. If Sidebar is visible -> Hide Sidebar (Enter Double Column)
        if isSidebarVisible {
            setSidebarVisible(false)
            isUnfoldingLayout = false
            return
        }

        // 2. If Note List is visible -> Check unfolding direction
        if isNotelistVisible {
            if isUnfoldingLayout {
                // Direction: Unfolding -> Show Sidebar (Return to Full)
                setSidebarVisible(true)
                isUnfoldingLayout = false
            } else {
                // Direction: Folding -> Hide Note List (Enter Focus Mode)
                setNotelistVisible(false)
            }
            return
        }

        // 3. If Note List is hidden -> Show Note List (Start Unfolding)
        setNotelistVisible(true)
        isUnfoldingLayout = true
    }

    @IBAction func toggleSidebarPanel(_ sender: Any) {
        guard sidebarSplitView != nil else { return }
        isSidebarVisible ? hideSidebar(sender) : showSidebar(sender)
    }

    @IBAction func toggleSplitMode(_ sender: Any) {
        saveTitleSafely()
        let newMode = !sessionSplitMode
        sessionSplitMode = newMode

        // Trigger UI update
        // If currently in Preview Mode, exit it.
        // The disablePreview() logic will check splitViewMode and automatically transition to Split Mode.
        if sessionPreviewMode {
            disablePreview()
        } else {
            applyEditorModePreferenceChange()
        }

        // Update Button Icon
        if let button = toggleSplitButton {
            // Prefer split icon; fall back if the single icon asset is missing.
            let iconName = newMode ? "icon_editor_split" : "icon_editor_single"
            let image = NSImage(named: iconName) ?? NSImage(named: "icon_editor_split")
            if let image {
                image.isTemplate = true
                button.image = image
            }
        }
        updateToolbarButtonTints()
    }

    // MARK: - Gesture Handling
    override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
        axis == .horizontal
    }

    override func swipe(with event: NSEvent) {
        swipe(deltaX: event.deltaX)
    }

    override func scrollWheel(with event: NSEvent) {
        if !NSEvent.isSwipeTrackingFromScrollEventsEnabled {
            super.scrollWheel(with: event)
            return
        }

        switch event.phase {
        case .began:
            isHandlingScrollEvent = true
            swipeLeftExecuted = false
            swipeRightExecuted = false
            scrollDeltaX = 0
        case .changed:
            guard isHandlingScrollEvent else {
                break
            }

            let directionChanged = scrollDeltaX.sign != event.scrollingDeltaX.sign

            guard !directionChanged else {
                scrollDeltaX = event.scrollingDeltaX
                break
            }

            scrollDeltaX += event.scrollingDeltaX

            // throttle
            guard abs(scrollDeltaX) > 50 else {
                break
            }

            let flippedScrollDelta = scrollDeltaX * -1
            let swipedLeft = flippedScrollDelta > 0

            switch (swipedLeft, swipeLeftExecuted, swipeRightExecuted) {
            case (true, false, _):  // swiped left
                swipeLeftExecuted = true
                swipeRightExecuted = false  // allow swipe back (right)
            case (false, _, false):  // swiped right
                swipeLeftExecuted = false  // allow swipe back (left)
                swipeRightExecuted = true
            default:
                super.scrollWheel(with: event)
                return
            }
            swipe(deltaX: flippedScrollDelta)
            return
        case .cancelled,
            .ended,
            .mayBegin:
            isHandlingScrollEvent = false
        default:
            break
        }

        super.scrollWheel(with: event)
    }

    func swipe(deltaX: CGFloat) {
        guard deltaX != 0 else { return }

        let swipedLeft = deltaX > 0

        if swipedLeft {
            // 向左滑：优先隐藏 sidebar，然后隐藏 notelist
            if isSidebarVisible {
                hideSidebar("")
            } else if isNotelistVisible {
                hideNoteList("")
            }
        } else {
            // 向右滑：优先显示 notelist，然后显示 sidebar
            if !isNotelistVisible {
                showNoteList("")
            } else if !isSidebarVisible {
                showSidebar("")
            }
        }
    }

    // MARK: - Split View Delegate
    func splitViewWillResizeSubviews(_ notification: Notification) {
        editArea.updateTextContainerInset()
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView,
            splitView == sidebarSplitView
        else { return }
        (sidebarSplitView as? ThemedSplitView)?.applyDividerColor()
        updateSidebarColumnWidth()
        checkSidebarConstraint()
        updateToolbarButtonTints()
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView == sidebarSplitView,
            dividerIndex == 0,
            proposedPosition > 0,
            proposedPosition <= Theme.Metrics.sidebarCollapseSnapWidth
        {
            return 0
        }

        return proposedPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView == sidebarSplitView && dividerIndex == 0 {
            return 0
        }

        if dividerIndex == 0 && UserDefaultsManagement.isSingleMode {
            return 0
        }
        return proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView == sidebarSplitView && dividerIndex == 0 {
            return LayoutConstants.maxSidebarWidth
        }

        if dividerIndex == 0 && UserDefaultsManagement.isSingleMode {
            return 0
        }
        return proposedMaximumPosition
    }

    // MARK: - View Resize
    func viewDidResize() {
        checkSidebarConstraint()
        checkTitlebarTopConstraint()
        updateSidebarColumnWidth()

        if view.window?.inLiveResize != true {
            normalizeNotelistWidth(saveState: false)
        }

        handleEditorContentResize()
    }

    func handleEditorContentResize() {
        editArea.updateTextContainerInset()
        if view.window?.inLiveResize == true {
            needsPreviewLayoutAfterLiveResize = true
            return
        }
        updatePreviewLayoutDuringResize()
        schedulePreviewLayoutUpdateAfterResize()
    }

    private func updatePreviewLayoutDuringResize() {
        guard let previewView = editArea.markdownView else { return }

        let targetBounds: CGRect
        if let previewScroll = previewScrollView {
            targetBounds = previewScroll.bounds
        } else if let container = previewView.superview {
            targetBounds = container.bounds
        } else {
            return
        }

        let targetFrame = CGRect(origin: .zero, size: targetBounds.size)
        if previewView.frame != targetFrame {
            previewView.frame = targetFrame
        }
    }

    func handleWindowDidEndLiveResize() {
        guard needsPreviewLayoutAfterLiveResize else { return }
        needsPreviewLayoutAfterLiveResize = false
        schedulePreviewLayoutUpdateAfterResize()
    }

    private func schedulePreviewLayoutUpdateAfterResize() {
        guard shouldShowPreview else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.layoutSubtreeIfNeeded()
            self.updatePreviewLayoutDuringResize()
        }
    }

    // MARK: - Table and Sidebar Layout
    func updateSidebarColumnWidth() {
        guard sidebarWidth > 0,
            let column = storageOutlineView?.tableColumns.first
        else { return }

        let clipWidth = sidebarScrollView?.contentView.bounds.width ?? 0
        let fallbackWidth = sidebarSplitView?.subviews.first?.bounds.width ?? storageOutlineView.bounds.width
        let measuredWidth = clipWidth > 1 ? clipWidth : fallbackWidth
        let targetWidth = max(0, floor(measuredWidth))
        if column.width != targetWidth {
            column.width = targetWidth
        }
        if let outline = storageOutlineView, outline.frame.width != targetWidth {
            outline.setFrameSize(NSSize(width: targetWidth, height: outline.frame.height))
        }

        if let scrollView = sidebarScrollView {
            let clipView = scrollView.contentView
            let origin = clipView.bounds.origin
            if origin.x != 0 {
                clipView.scroll(to: NSPoint(x: 0, y: origin.y))
                scrollView.reflectScrolledClipView(clipView)
            }
        }
    }

    func reloadSideBar() {
        guard let outline = storageOutlineView else {
            return
        }

        sidebarTimer.invalidate()
        sidebarTimer = Timer.scheduledTimer(timeInterval: 1.2, target: outline, selector: #selector(outline.reloadSidebar), userInfo: nil, repeats: false)
    }

    func setTableRowHeight() {
        notesTableView.rowHeight = CGFloat(52)
        notesTableView.selectionHighlightStyle = .none
        notesTableView.reloadData()
    }

}
