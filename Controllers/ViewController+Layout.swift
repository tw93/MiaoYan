import Cocoa

// MARK: - Layout Management
extension ViewController {

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

    func updateDividers() {
        guard sidebarSplitView != nil && splitView != nil else { return }
        setDividerColor(for: sidebarSplitView, hidden: sidebarWidth == 0)
        setDividerColor(for: splitView, hidden: notelistWidth == 0)
    }

    func setDividerColor(for splitView: NSSplitView, hidden: Bool) {
        let baseColor = Theme.backgroundColor
        var color: NSColor = baseColor
        guard !hidden else {
            splitView.setValue(color, forKey: "dividerColor")
            splitView.needsDisplay = true
            return
        }

        let named = NSColor(named: "divider") ?? NSColor.separatorColor
        let appearance = view.effectiveAppearance
        var cg: CGColor?
        appearance.performAsCurrentDrawingAppearance {
            cg = named.cgColor
        }
        if let cg, let fixed = NSColor(cgColor: cg) {
            color = fixed
        } else {
            color = named
        }

        splitView.setValue(color, forKey: "dividerColor")
        splitView.needsDisplay = true
    }

    func checkSidebarConstraint() {
        if sidebarSplitView.subviews[0].frame.width < 50, !UserDefaultsManagement.isWillFullScreen {
            searchTopConstraint.constant = 25.0
            return
        }
        searchTopConstraint.constant = 11.0
    }

    func checkTitlebarTopConstraint() {
        if splitView.subviews[0].frame.width < 50, !UserDefaultsManagement.isWillFullScreen {
            titiebarHeight.constant = 64.0
            titleTopConstraint.constant = 30.0
            return
        }
        titiebarHeight.constant = 52.0
        titleTopConstraint.constant = 16.0
    }

    // MARK: - Sidebar Management

    func hideSidebar(_ sender: Any) {
        guard sidebarWidth > 0 else { return }

        // Only save the width if we're not in presentation mode transition
        // (presentation mode should have already saved the correct width)
        if !UserDefaultsManagement.presentation {
            UserDefaultsManagement.realSidebarSize = Int(sidebarWidth)
        }

        sidebarSplitView.setPosition(0, ofDividerAt: 0)
        updateDividers()
        editArea.updateTextContainerInset()
    }

    func showSidebar(_ sender: Any) {
        guard sidebarWidth == 0 else { return }

        // Ensure we have a reasonable minimum width for sidebar
        let savedWidth = UserDefaultsManagement.realSidebarSize
        let targetWidth = max(savedWidth, 138)  // 138 is the default minimum

        // Update saved value if it was too small
        if savedWidth < 138 {
            UserDefaultsManagement.realSidebarSize = 138
        }

        sidebarSplitView.setPosition(CGFloat(targetWidth), ofDividerAt: 0)

        if notelistWidth == 0 {
            expandNoteList()
        }

        updateDividers()
        editArea.updateTextContainerInset()
    }

    // MARK: - Note List Management

    func showNoteList(_ sender: Any) {
        if notelistWidth == 0 {
            if sidebarWidth == 0 {
                showSidebar(sender)
            } else {
                expandNoteList()
            }
        }
        editArea.updateTextContainerInset()
    }

    func hideNoteList(_ sender: Any) {
        if notelistWidth > 0 {
            UserDefaultsManagement.sidebarSize = Int(notelistWidth)
            splitView.shouldHideDivider = true
            splitView.setPosition(0, ofDividerAt: 0)

            hideSidebar("")

            updateDividers()
        }
        editArea.updateTextContainerInset()
    }

    private func expandNoteList() {
        let size = UserDefaultsManagement.sidebarSize == 0 ? 280 : UserDefaultsManagement.sidebarSize
        splitView.shouldHideDivider = false
        splitView.setPosition(CGFloat(size), ofDividerAt: 0)
        updateDividers()
    }

    // MARK: - Toggle Actions

    @IBAction func toggleNoteList(_ sender: Any) {
        guard splitView != nil else { return }

        if notelistWidth == 0 {
            showNoteList(sender)
        } else {
            hideNoteList(sender)
        }
    }

    @IBAction func toggleSidebarPanel(_ sender: Any) {
        guard sidebarSplitView != nil else { return }

        if sidebarWidth == 0 {
            showSidebar(sender)
        } else {
            hideSidebar(sender)
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

        guard let vc = ViewController.shared() else { return }
        let siderbarSize = Int(vc.sidebarSplitView.subviews[0].frame.width)
        let notelistSize = Int(vc.splitView.subviews[0].frame.width)

        let swipedLeft = deltaX > 0

        if swipedLeft {
            if siderbarSize > 0 {
                hideSidebar("")
            } else {
                if notelistSize > 0 {
                    hideNoteList("")
                }
            }

        } else {
            if notelistSize == 0 {
                showNoteList("")
            } else {
                if siderbarSize == 0 {
                    showSidebar("")
                }
            }
        }
    }

    // MARK: - Split View Delegate

    func splitViewWillResizeSubviews(_ notification: Notification) {
        editArea.updateTextContainerInset()
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        updateDividers()
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
            return 280
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
        updateDividers()

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
