import Cocoa

// MARK: - Layout Management
extension ViewController {

    // MARK: - Layout Constants
    private enum LayoutConstants {
        static let minSidebarWidth: CGFloat = 138
        static let maxSidebarWidth: CGFloat = 280
        static let defaultNotelistWidth: CGFloat = 280
        // The window's unified toolbar centres the traffic lights 26.5pt
        // down; the column headers sit on that line in every layout. A
        // column that starts at the window's left edge moves its first
        // control past the traffic lights instead of below them.
        static let searchTop: CGFloat = 12.0
        static let searchLeadingNormal: CGFloat = 13.0
        static let titlebarHeight: CGFloat = 52.0
        /// The title's capitals centred on the traffic lights and the
        /// title bar buttons; at 14 they sat 1.25pt low (2026-11-17).
        static let titleTop: CGFloat = 13.0
        /// The title's first stroke on the editor text's left edge (29pt from
        /// the column line at the default margin); 25 stood 4pt left of it.
        static let titleLeadingNormal: CGFloat = 29.0
        static let titleBarActionsTop: CGFloat = 16.0
        /// Where a leftmost column's first control starts: the traffic
        /// lights end 79pt in, plus the gap the sidebar leaves beside them.
        static let besideTrafficLights: CGFloat = 92.0
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

    var isSidebarVisible: Bool {
        guard let sidebarView = sidebarSplitView?.subviews.first else { return false }
        return !sidebarView.isHidden && sidebarWidth > Theme.Metrics.collapsedSplitWidthEpsilon
    }

    var isNotelistVisible: Bool {
        guard let noteListView = splitView?.subviews.first else { return false }
        return !noteListView.isHidden && notelistWidth > Theme.Metrics.collapsedSplitWidthEpsilon
    }

    // MARK: - Layout Management Methods
    func checkSidebarConstraint() {
        let isSidebarCollapsed = !isSidebarVisible && !UserDefaultsManagement.isWillFullScreen
        searchTopConstraint.constant = LayoutConstants.searchTop
        updateSearchLeadingInset(isSidebarCollapsed ? LayoutConstants.besideTrafficLights : LayoutConstants.searchLeadingNormal)
    }

    func checkTitlebarTopConstraint() {
        let isNarrow = !isNotelistVisible && !UserDefaultsManagement.isWillFullScreen
        let isEditorOnly = isNarrow && !isSidebarVisible

        titiebarHeight.constant = LayoutConstants.titlebarHeight
        titleTopConstraint.constant = LayoutConstants.titleTop
        updateTitleLeadingInset(isEditorOnly ? LayoutConstants.besideTrafficLights : LayoutConstants.titleLeadingNormal)
        updateTitleBarActionsTop(LayoutConstants.titleBarActionsTop)
    }

    private func updateSearchLeadingInset(_ inset: CGFloat) {
        guard let search, let container = search.superview else { return }
        for constraint in container.constraints where constraint.firstItem === search && constraint.firstAttribute == .leading {
            constraint.constant = inset
        }
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
            // Opening passes through widths under the minimum, where the
            // resize callback collapses the list and hides the divider again;
            // the list ended open with no line beside it (2026-11-17).
            splitView.shouldHideDivider = false

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

    static let sidebarSplitAutosaveName = "SidebarSplitView"
    static let noteListSplitAutosaveName = "EditorSplitView"

    /// A presentation or PPT collapses the sidebar and the note list, and
    /// AppKit autosaves split positions after the change, on a later turn of
    /// the run loop. Quitting inside one opened the next launch with no
    /// sidebar or note list (I-68), and opening the columns again on quit did
    /// not help: the process exits before AppKit writes the open positions.
    /// So the two split views stop autosaving while the presentation holds
    /// the columns, and the saved positions stay the ones from before it.
    func pauseColumnAutosave() {
        sidebarSplitView?.autosaveName = nil
        splitView?.autosaveName = nil
    }

    func resumeColumnAutosave() {
        sidebarSplitView?.autosaveName = Self.sidebarSplitAutosaveName
        splitView?.autosaveName = Self.noteListSplitAutosaveName
    }

    /// Opens the columns a presentation hid when the app quits inside it, so
    /// the window state the quit records matches them.
    func restoreColumnsHiddenByPresentation() {
        guard sessionPresentationMode || sessionMagicPPTMode else { return }
        if presentationRestoresNoteList { showNoteList("") }
        if presentationRestoresSidebar { showSidebar("") }
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
        if splitView == sidebarSplitView, dividerIndex == 0, proposedPosition > 0 {
            // Under the snap the sidebar collapses; above it the divider holds at
            // the minimum setSidebarVisible restores, since a narrower sidebar
            // truncated the English wordmark to "MiaoY…".
            return proposedPosition <= Theme.Metrics.sidebarCollapseSnapWidth ? 0 : max(proposedPosition, LayoutConstants.minSidebarWidth)
        }

        return proposedPosition
    }

    /// The split view's autosave restores the width the divider last stopped
    /// at, which an older build let fall under the minimum (126.5pt on the
    /// maintainer's Mac); a visible sidebar narrower than that is widened.
    func widenSidebarToMinimumIfNeeded() {
        let width = sidebarWidth
        guard width > 0, width < LayoutConstants.minSidebarWidth else { return }
        sidebarSplitView.setPosition(LayoutConstants.minSidebarWidth, ofDividerAt: 0)
        updateSidebarColumnWidth()
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
