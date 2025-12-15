import Cocoa

// MARK: - Layout Management
extension ViewController {

    // MARK: - Layout Constants
    private enum LayoutConstants {
        static let minSidebarWidth: CGFloat = 138
        static let maxSidebarWidth: CGFloat = 280
        static let defaultNotelistWidth: CGFloat = 280
        static let narrowThreshold: CGFloat = 50
        static let searchTopNarrow: CGFloat = 34.0
        static let searchTopNormal: CGFloat = 13.0
        static let titlebarHeightNarrow: CGFloat = 64.0
        static let titlebarHeightNormal: CGFloat = 52.0
        static let titleTopNarrow: CGFloat = 30.0
        static let titleTopNormal: CGFloat = 16.0
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

    // MARK: - Layout Management Methods
    func checkSidebarConstraint() {
        let isNarrow = sidebarWidth < LayoutConstants.narrowThreshold && !UserDefaultsManagement.isWillFullScreen
        searchTopConstraint.constant = isNarrow ? LayoutConstants.searchTopNarrow : LayoutConstants.searchTopNormal
    }

    func checkTitlebarTopConstraint() {
        let isNarrow = notelistWidth < LayoutConstants.narrowThreshold && !UserDefaultsManagement.isWillFullScreen
        titiebarHeight.constant = isNarrow ? LayoutConstants.titlebarHeightNarrow : LayoutConstants.titlebarHeightNormal
        titleTopConstraint.constant = isNarrow ? LayoutConstants.titleTopNarrow : LayoutConstants.titleTopNormal
    }

    // MARK: - Core Panel Operations

    private var isPresentationMode: Bool {
        UserDefaultsManagement.presentation || UserDefaultsManagement.magicPPT
    }

    private func setSidebarVisible(_ visible: Bool, saveState: Bool = true) {
        if visible {
            let savedWidth = UserDefaultsManagement.realSidebarSize
            let targetWidth = max(savedWidth, Int(LayoutConstants.minSidebarWidth))

            if savedWidth < Int(LayoutConstants.minSidebarWidth) {
                UserDefaultsManagement.realSidebarSize = Int(LayoutConstants.minSidebarWidth)
            }

            sidebarSplitView.setPosition(CGFloat(targetWidth), ofDividerAt: 0)
        } else {
            if saveState && !isPresentationMode {
                UserDefaultsManagement.realSidebarSize = Int(sidebarWidth)
            }
            sidebarSplitView.setPosition(0, ofDividerAt: 0)
        }
        editArea.updateTextContainerInset()
    }

    func ensurePanelsVisibleAtStartup() {
        guard !UserDefaultsManagement.isSingleMode else { return }
        let shouldShowSidebar = sidebarWidth > 0
        let shouldShowNotelist = notelistWidth > 0

        if shouldShowSidebar && !shouldShowNotelist {
            showNoteList("")
        }
    }

    private func setNotelistVisible(_ visible: Bool, saveState: Bool = true) {
        if visible {
            let savedWidth = UserDefaultsManagement.sidebarSize
            let targetWidth = savedWidth > 0 ? savedWidth : Int(LayoutConstants.defaultNotelistWidth)
            splitView.shouldHideDivider = false
            splitView.setPosition(CGFloat(targetWidth), ofDividerAt: 0)
        } else {
            if saveState && !isPresentationMode {
                UserDefaultsManagement.sidebarSize = Int(notelistWidth)
            }
            splitView.shouldHideDivider = true
            splitView.setPosition(0, ofDividerAt: 0)
        }
        editArea.updateTextContainerInset()
    }

    // MARK: - Sidebar Management

    func hideSidebar(_ sender: Any) {
        guard sidebarWidth > 0 else { return }

        // 隐藏 sidebar → 不影响 notelist（允许两栏模式）
        setSidebarVisible(false)
    }

    func showSidebar(_ sender: Any) {
        guard sidebarWidth == 0 else { return }

        // 显示 sidebar → 自动显示 notelist
        if notelistWidth == 0 {
            setNotelistVisible(true)
        }
        setSidebarVisible(true)
    }

    // MARK: - Note List Management

    func showNoteList(_ sender: Any) {
        guard notelistWidth == 0 else { return }

        // 显示 notelist → 不强制显示 sidebar（允许两栏模式）
        setNotelistVisible(true)
    }

    func hideNoteList(_ sender: Any) {
        guard notelistWidth > 0 else { return }

        // 隐藏 notelist → 自动隐藏 sidebar
        setNotelistVisible(false)
        if sidebarWidth > 0 {
            setSidebarVisible(false)
        }
    }

    // MARK: - Toggle Actions
    @IBAction func toggleNoteList(_ sender: Any) {
        guard splitView != nil else { return }
        notelistWidth == 0 ? showNoteList(sender) : hideNoteList(sender)
    }

    @IBAction func toggleLayoutCycle(_ sender: Any) {
        guard splitView != nil, sidebarSplitView != nil else { return }

        // 1. If Sidebar is visible -> Hide Sidebar (Enter Double Column)
        if sidebarWidth > 0 {
            setSidebarVisible(false)
            isUnfoldingLayout = false
            return
        }

        // 2. If Note List is visible -> Check unfolding direction
        if notelistWidth > 0 {
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
        sidebarWidth == 0 ? showSidebar(sender) : hideSidebar(sender)
    }

    @IBAction func toggleSplitMode(_ sender: Any) {
        let newMode = !UserDefaultsManagement.splitViewMode
        UserDefaultsManagement.splitViewMode = newMode

        // Trigger UI update
        // If currently in Preview Mode, exit it.
        // The disablePreview() logic will check splitViewMode and automatically transition to Split Mode.
        if UserDefaultsManagement.preview {
            UserDefaultsManagement.preview = false
        } else {
            applyEditorModePreferenceChange()
        }

        // Update Button Icon
        if let button = toggleSplitButton {
            // Use custom icons for two states (single/split)
            let iconName = newMode ? "icon_editor_split" : "icon_editor_single"
            if let image = NSImage(named: iconName) {
                image.isTemplate = true
                button.image = image
            }
        }
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
            if sidebarWidth > 0 {
                hideSidebar("")
            } else if notelistWidth > 0 {
                hideNoteList("")
            }
        } else {
            // 向右滑：优先显示 notelist，然后显示 sidebar
            if notelistWidth == 0 {
                showNoteList("")
            } else if sidebarWidth == 0 {
                showSidebar("")
            }
        }
    }

    // MARK: - Split View Delegate
    func splitViewWillResizeSubviews(_ notification: Notification) {
        editArea.updateTextContainerInset()
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {}

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

        if !refilled {
            refilled = true
            DispatchQueue.main.async {
                self.refillEditArea(previewOnly: true)
                self.refilled = false
            }
        }
    }

    // MARK: - Table and Sidebar Layout
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
