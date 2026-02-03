import Cocoa
import Foundation
import Prettier
import PrettierMarkdown

// MARK: - Editor Management
extension ViewController {
    // MARK: - Timing Constants

    private enum EditorTiming {
        static let previewFocusDelay: TimeInterval = 0.1
        static let scrollRestoreDelay: TimeInterval = 0.3
        static let scrollSyncResetDelay: TimeInterval = 0.016  // ~60fps (1/60 second)
        static let presentationLayoutDelay: TimeInterval = 0.15
        static let pptSlideTransitionDelay: TimeInterval = 0.3
        static let pptFocusDelay: TimeInterval = 0.6

        // Split View timing
        static let splitScrollSyncDelay: TimeInterval = 0.05  // Allow JS rendering + callback
        static let splitModeTransitionDelay: TimeInterval = 0.08  // Animation duration
        static let imageLoadTimeout: TimeInterval = 0.35  // WebView image load timeout
    }

    // MARK: - WebView Helper

    /// Show WebView - centralized method to avoid duplication
    private func showWebView() {
        editArea.markdownView?.alphaValue = 1.0
        editArea.markdownView?.isHidden = false
    }

    /// Hide WebView - centralized method to avoid duplication
    private func hideWebView() {
        editArea.markdownView?.isHidden = true
        editArea.markdownView?.alphaValue = 1.0
    }

    /// Restore editor scroll view alpha if it was hidden during startup
    private func revealEditorIfNeeded() {
        if editAreaScroll.alphaValue < 1 {
            editAreaScroll.alphaValue = 1
        }
    }

    // MARK: - Preview Management
    func enablePreview() {
        // Debounce rapid repeated calls (within 0.15 seconds)
        let now = Date().timeIntervalSince1970
        let timeSinceLastCall = now - lastEnablePreviewTime
        if timeSinceLastCall < 0.15 && UserDefaultsManagement.preview {
            return
        }
        lastEnablePreviewTime = now

        if !UserDefaultsManagement.preview {
            savedEditorSelection = editArea.selectedRange()
            savedEditorScrollRatio = getScrollTop()
            savedEditorNoteURL = EditTextView.note?.url
        }

        if !UserDefaultsManagement.magicPPT {
            UserDefaultsManagement.preview = true
        }

        isFocusedTitle = titleLabel.hasFocus()
        cancelTextSearch()

        // Use animated: false to ensure immediate layout update
        editorContentSplitView?.setDisplayMode(.previewOnly, animated: false)

        preparePreviewContainer(hidden: false)


        previewScrollView?.hasVerticalScroller = true

        ensureNoteSelection(preferLastSelected: true, preserveScrollPosition: true)

        refillEditArea()

        if notesTableView.selectedRow == -1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self else { return }
                self.ensureNoteSelection(preferLastSelected: true, preserveScrollPosition: true)
                if self.notesTableView.selectedRow >= 0 {
                    self.refillEditArea(force: true)
                }
            }
        }

        titleLabel.isEditable = false
        // Disable editor's find bar to prevent Cmd+F from being intercepted by NSTextView
        editArea.usesFindBar = false
        // Hide editor scrollbar to prevent overlap with preview scrollbar
        editAreaScroll.hasVerticalScroller = false
        editAreaScroll.hasHorizontalScroller = false

        // Restore editor scroll alpha if it was hidden during startup
        revealEditorIfNeeded()

        // Make WebView the first responder to handle Cmd+F properly
        DispatchQueue.main.asyncAfter(deadline: .now() + EditorTiming.previewFocusDelay) {
            self.editArea.window?.makeFirstResponder(self.editArea.markdownView)
        }
        if UserDefaultsManagement.previewLocation == "Editing", !UserDefaultsManagement.isOnExport {
            let scrollPre = getScrollTop()
            DispatchQueue.main.asyncAfter(deadline: .now() + EditorTiming.scrollRestoreDelay) {
                self.editArea.markdownView?.scrollToPosition(pre: scrollPre)
            }
        }
    }

    private func enableSplitViewMode() {
        guard let contentSplitView = editorContentSplitView,
            previewScrollView != nil
        else {
            return
        }
        // UX: Ensure a note is selected when entering split mode (prefer last selected note)
        ensureNoteSelection(preferLastSelected: true)

        // Force layout update BEFORE setting display mode to ensure correct bounds
        contentSplitView.layoutSubtreeIfNeeded()

        // First-time use: setDisplayMode will default to 50/50 split when position is 0
        // Set split view to side-by-side mode
        contentSplitView.setDisplayMode(.sideBySide, animated: false)

        // Force layout update to ensure correct bounds
        contentSplitView.layoutSubtreeIfNeeded()

        preparePreviewContainer(hidden: false)

        // Ensure editor content reflects the selected note alongside preview
        refillEditArea(force: true)

        // Editor remains editable in split mode and title bar stays visible
        titleBarView.isHidden = false
        titleLabel.isHidden = false
        titleLabel.isEditable = true
        editArea.usesFindBar = false
        editAreaScroll.hasVerticalScroller = false
        editAreaScroll.hasHorizontalScroller = true
        previewScrollView?.hasVerticalScroller = true
        previewScrollView?.hasHorizontalScroller = false

        startSplitScrollSync()

        // Keep editor focused
        if !isFocusedTitle {
            focusEditArea()
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func disablePreview() {
        guard !UserDefaultsManagement.magicPPT else { return }


        // Save preview scroll position before disabling
        if let webView = editArea.markdownView {
            let applyPreviewDisable: (_ ratio: CGFloat?) -> Void = { [weak self, weak webView] ratio in
                guard let self else { return }
                guard let webView else { return }

                var storedSelection = self.savedEditorSelection
                var storedScrollRatio = self.savedEditorScrollRatio
                let storedNoteURL = self.savedEditorNoteURL
                let currentNoteURL = EditTextView.note?.url
                let shouldUseStoredState = storedNoteURL != nil && storedNoteURL == currentNoteURL
                if !shouldUseStoredState {
                    storedSelection = nil
                    storedScrollRatio = nil
                }
                let shouldRestoreCursor = storedSelection == nil
                self.savedEditorSelection = nil
                self.savedEditorScrollRatio = nil
                self.savedEditorNoteURL = nil

                UserDefaultsManagement.preview = false
                // Close search bar if open
                webView.hideSearchBar()
                self.hideWebView()
                webView.resetTemplateState()
                webView.loadHTMLString("<html><body style='background:transparent;'></body></html>", baseURL: nil)
                self.refillEditArea(suppressSave: true)
                self.editArea.usesFindBar = false
                // Restore editor scrollbar
                self.editAreaScroll.hasVerticalScroller = true
                self.editAreaScroll.hasHorizontalScroller = true
                // Restore editor scroll alpha
                self.revealEditorIfNeeded()

                let normalizedRatio = ratio.map { min(max($0, 0), 1) }
                let ratioToRestore = shouldUseStoredState ? (storedScrollRatio ?? normalizedRatio) : nil

                DispatchQueue.main.asyncAfter(deadline: .now() + EditorTiming.previewFocusDelay) { [weak self] in
                    guard let self = self else { return }

                    if let ratio = ratioToRestore,
                        ratio > 0,
                        let documentView = self.editAreaScroll.documentView
                    {
                        let contentHeight = self.editAreaScroll.contentSize.height
                        let scrollHeight = documentView.bounds.height
                        let offset = max(scrollHeight - contentHeight, 0)
                        if offset > 0 {
                            let scrollTop = offset * ratio
                            documentView.scroll(NSPoint(x: 0, y: scrollTop))
                        }
                    }

                    self.titleLabel.isEditable = true
                    if !self.isFocusedTitle {
                        self.focusEditArea(restoreCursor: shouldRestoreCursor)
                    }

                    if let storedSelection,
                        let storage = self.editArea.textStorage
                    {
                        let clampedLocation = min(max(storedSelection.location, 0), storage.length)
                        let clampedLength = min(max(storedSelection.length, 0), max(storage.length - clampedLocation, 0))
                        let clampedRange = NSRange(location: clampedLocation, length: clampedLength)
                        self.editArea.setSelectedRange(clampedRange)
                    }

                    // Restore editor mode based on user preference
                    if self.needsEditorModeUpdateAfterPreview {
                        self.needsEditorModeUpdateAfterPreview = false
                        self.applyEditorModePreferenceChange()
                    } else if UserDefaultsManagement.splitViewMode {
                        self.enableSplitViewMode()
                    } else {
                        self.editorContentSplitView?.setDisplayMode(.editorOnly, animated: false)

                        // Clear preview views AFTER setDisplayMode
                        self.previewScrollView?.documentView = nil
                        self.previewScrollView?.isHidden = true
                        self.previewScrollView?.hasVerticalScroller = false
                        self.editAreaScroll.hasVerticalScroller = true
                    }
                }
            }

            webView.evaluateJavaScript("window.pageYOffset") { scrollTop, _ in
                guard let scrollTopNumber = scrollTop as? NSNumber else {
                    applyPreviewDisable(nil)
                    return
                }
                let scrollTopValue = CGFloat(truncating: scrollTopNumber)

                webView.evaluateJavaScript("Math.max(document.body.scrollHeight - window.innerHeight, 0)") { maxScroll, _ in
                    guard let maxScrollNumber = maxScroll as? NSNumber else {
                        applyPreviewDisable(nil)
                        return
                    }
                    let maxScrollValue = CGFloat(truncating: maxScrollNumber)
                    guard maxScrollValue > 0 else {
                        applyPreviewDisable(nil)
                        return
                    }

                    let scrollRatio = scrollTopValue / maxScrollValue
                    applyPreviewDisable(scrollRatio)
                }
            }
            return
        }

        // Fallback if no webView (shouldn't happen but for safety)
        var storedSelection = savedEditorSelection
        var storedScrollRatio = savedEditorScrollRatio
        let storedNoteURL = savedEditorNoteURL
        let currentNoteURL = EditTextView.note?.url
        let shouldUseStoredState = storedNoteURL != nil && storedNoteURL == currentNoteURL
        if !shouldUseStoredState {
            storedSelection = nil
            storedScrollRatio = nil
        }
        let shouldRestoreCursor = storedSelection == nil
        savedEditorSelection = nil
        savedEditorScrollRatio = nil
        savedEditorNoteURL = nil
        UserDefaultsManagement.preview = false
        // Close search bar if somehow exists
        editArea.markdownView?.hideSearchBar()
        refillEditArea(suppressSave: true)
        editArea.usesFindBar = false
        // Restore editor scrollbar
        editAreaScroll.hasVerticalScroller = true
        editAreaScroll.hasHorizontalScroller = true
        // Restore editor scroll alpha
        revealEditorIfNeeded()
        DispatchQueue.main.async {
            self.titleLabel.isEditable = true
            if !self.isFocusedTitle {
                self.focusEditArea(restoreCursor: shouldRestoreCursor)
            }
            if let storedSelection,
                let storage = self.editArea.textStorage
            {
                let clampedLocation = min(max(storedSelection.location, 0), storage.length)
                let clampedLength = min(max(storedSelection.length, 0), max(storage.length - clampedLocation, 0))
                let clampedRange = NSRange(location: clampedLocation, length: clampedLength)
                self.editArea.setSelectedRange(clampedRange)
            }
            if let ratio = storedScrollRatio,
                ratio > 0,
                let documentView = self.editAreaScroll.documentView
            {
                let contentHeight = self.editAreaScroll.contentSize.height
                let scrollHeight = documentView.bounds.height
                let offset = max(scrollHeight - contentHeight, 0)
                if offset > 0 {
                    let scrollTop = offset * ratio
                    documentView.scroll(NSPoint(x: 0, y: scrollTop))
                }
            }
        }

        // Restore editor mode based on user preference
        if needsEditorModeUpdateAfterPreview {
            needsEditorModeUpdateAfterPreview = false
            applyEditorModePreferenceChange()
        } else if UserDefaultsManagement.splitViewMode {
            enableSplitViewMode()
        } else {
            editorContentSplitView?.setDisplayMode(.editorOnly, animated: false)

            // Clear preview views AFTER setDisplayMode
            previewScrollView?.documentView = nil
            previewScrollView?.isHidden = true
            previewScrollView?.hasVerticalScroller = false
            editAreaScroll.hasVerticalScroller = true
        }
    }

    private func disableSplitViewMode() {
        guard let contentSplitView = editorContentSplitView else { return }

        // Set display mode back to editor only (no animation for immediate effect)
        contentSplitView.setDisplayMode(.editorOnly, animated: false)
        stopSplitScrollSync()

        // Clear preview container
        previewScrollView?.documentView = nil
        previewScrollView?.isHidden = true
        editArea.markdownView?.isHidden = true
        previewScrollView?.hasVerticalScroller = false
        editAreaScroll.hasVerticalScroller = true

        // Split mode doesn't affect preview state - don't set preview=false here
        titleLabel.isEditable = true

        if !isFocusedTitle {
            focusEditArea()
        }
    }

    func togglePreview() {
        saveTitleSafely()

        if UserDefaultsManagement.preview {
            disablePreview()
        } else {
            enablePreview()
        }
    }

    @IBAction func toggleSplitView(_ sender: Any) {
        saveTitleSafely()
        UserDefaultsManagement.splitViewMode.toggle()

        if UserDefaultsManagement.splitViewMode {
            applyEditorModePreferenceChange()
        } else {
            applyEditorModePreferenceChange()
        }
    }

    // Debug helper - can call this from console or add a menu item
    @objc func resetSplitViewPosition() {
        UserDefaultsManagement.editorContentSplitPosition = 0
        if UserDefaultsManagement.splitViewMode {
            editorContentSplitView?.setDisplayMode(.sideBySide, animated: false)
        }
    }

    func applyEditorModePreferenceChange() {
        // Defer mode changes if in special modes (preview, presentation, PPT)
        guard !UserDefaultsManagement.isInSpecialMode else {
            needsEditorModeUpdateAfterPreview = true
            return
        }

        // Ensure split view is initialized
        guard editorContentSplitView != nil else {
            return
        }

        needsEditorModeUpdateAfterPreview = false

        if UserDefaultsManagement.splitViewMode {
            enableSplitViewMode()
        } else {
            disableSplitViewMode()
        }

        // Update toolbar button state (Unified split icon for both states)
        if let image = NSImage(named: "icon_editor_split") {
            image.isTemplate = true
            toggleSplitButton?.image = image
        }

    }

    private struct SplitScrollConfig {
        static let syncThreshold: CGFloat = 0.005
        static let scrollDifferenceThreshold: CGFloat = 0.5
    }

    private func makeTempNote() -> Note? {
        let tempProject = getSidebarProject() ?? storage.noteList.first?.project
        guard let project = tempProject else { return nil }
        let tempNote = Note(name: "", project: project, type: .markdown)
        tempNote.content = NSMutableAttributedString(string: "")
        return tempNote
    }

    // MARK: - Presentation Mode

    private func savePresentationLayout() {
        let currentSidebarWidth = sidebarWidth
        let currentNotelistWidth = notelistWidth

        if currentSidebarWidth > 86 {
            UserDefaultsManagement.realSidebarSize = Int(currentSidebarWidth)
        }
        if currentNotelistWidth > 0 {
            UserDefaultsManagement.sidebarSize = Int(currentNotelistWidth)
        }
        if let clipView = notesTableView.superview as? NSClipView {
            savedPresentationScrollPosition = clipView.bounds.origin
        }
    }

    private func restorePresentationLayout() {
        formatButton.isHidden = false
        previewButton.isHidden = false
        toggleListButton?.isHidden = false
        toggleSplitButton?.isHidden = false

        if sidebarWidth == 0 { showSidebar("") }
        if notelistWidth == 0 { showNoteList("") }
        checkTitlebarTopConstraint()

        if let savedPosition = savedPresentationScrollPosition,
            let clipView = notesTableView.superview as? NSClipView
        {
            clipView.setBoundsOrigin(savedPosition)
            savedPresentationScrollPosition = nil
        }
    }

    func enablePresentation() {
        // Ensure a note is selected before entering presentation mode
        ensureNoteSelection(preferLastSelected: true)

        UserDefaultsManagement.presentation = true
        savePresentationLayout()
        hideNoteList("")
        formatButton.isHidden = true
        previewButton.isHidden = true
        toggleListButton?.isHidden = true
        toggleSplitButton?.isHidden = true

        // Set up split view and preview container synchronously
        editorContentSplitView?.setDisplayMode(.previewOnly, animated: false)
        preparePreviewContainer(hidden: false)
        previewScrollView?.hasVerticalScroller = true
        previewScrollView?.isHidden = false

        // Force immediate content load
        if editArea.markdownView != nil {
            showWebView()
        }

        // Load content in presentation mode
        refillEditArea(previewOnly: true, force: true)
        presentationButton.state = .on
        presentationButton.contentTintColor = Theme.accentColor
        // Disable editor's find bar to prevent Cmd+F from being intercepted by NSTextView
        editArea.usesFindBar = false
        // Hide editor scrollbar to prevent overlap with preview scrollbar
        editAreaScroll.hasVerticalScroller = false
        editAreaScroll.hasHorizontalScroller = false
        if !UserDefaultsManagement.fullScreen {
            view.window?.toggleFullScreen(nil)
        }
        if !UserDefaultsManagement.isOnExportPPT {
            DispatchQueue.main.asyncAfter(deadline: .now() + EditorTiming.presentationLayoutDelay) {
                self.toast(message: I18n.str("🙊 Press ESC key to exit~"))
            }
        }
    }

    func disablePresentation() {
        presentationButton.state = .off
        presentationButton.contentTintColor = nil
        if UserDefaultsManagement.fullScreen {
            UserDefaultsManagement.fullScreen = false
            view.window?.toggleFullScreen(nil)
        }
        // Restore UI elements after fullscreen transition completes
        DispatchQueue.main.asyncAfter(deadline: .now() + EditorTiming.presentationLayoutDelay) {
            self.restorePresentationLayout()
            self.disablePreview()
            UserDefaultsManagement.presentation = false
            self.updateButtonStates()
        }
    }

    // MARK: - Helper Methods
    private func updateButtonStates() {
        DispatchQueue.main.async {
            self.previewButton.state = UserDefaultsManagement.preview ? .on : .off
            self.previewButton.contentTintColor = UserDefaultsManagement.preview ? Theme.accentColor : nil
            self.presentationButton.state = UserDefaultsManagement.presentation ? .on : .off
            self.presentationButton.contentTintColor = UserDefaultsManagement.presentation ? Theme.accentColor : nil
        }
    }

    func togglePresentation() {
        saveTitleSafely()
        // Handle both presentation and PPT modes
        if UserDefaultsManagement.presentation || UserDefaultsManagement.magicPPT {
            if UserDefaultsManagement.magicPPT {
                disableMiaoYanPPT()
            } else {
                disablePresentation()
            }
        } else {
            enablePresentation()
        }
    }
    // MARK: - PPT Mode

    func isMiaoYanPPT(needToast: Bool = true) -> Bool {
        guard let note = notesTableView.getSelectedNote() else {
            return false
        }
        let content = note.content.string
        if content.contains("---") {
            return true
        }
        if needToast {
            toast(message: I18n.str("😶‍🌫 No delimiter --- identification, Cannot use MiaoYan PPT~"))
        }
        return false
    }

    func toggleMagicPPT() {
        saveTitleSafely()
        if UserDefaultsManagement.magicPPT {
            disableMiaoYanPPT()
        } else {
            if !isMiaoYanPPT() {
                return
            }
            enableMiaoYanPPT()
        }
    }

    func enableMiaoYanPPT() {
        guard let vc = ViewController.shared() else {
            return
        }
        // Ensure a note is selected before entering PPT mode
        ensureNoteSelection(preferLastSelected: true)

        UserDefaultsManagement.magicPPT = true
        savePresentationLayout()
        hideNoteList("")
        hideNoteList("")
        formatButton.isHidden = true
        previewButton.isHidden = true
        toggleListButton?.isHidden = true
        toggleSplitButton?.isHidden = true
        DispatchQueue.main.async {
            vc.previewButton.state = .on
            vc.previewButton.contentTintColor = Theme.accentColor
            vc.presentationButton.state = .on
            vc.presentationButton.contentTintColor = Theme.accentColor
        }
        if !UserDefaultsManagement.fullScreen {
            view.window?.toggleFullScreen(nil)
        }

        // Set up split view and preview container synchronously
        editorContentSplitView?.setDisplayMode(.previewOnly, animated: false)
        preparePreviewContainer(hidden: false)
        previewScrollView?.hasVerticalScroller = true
        previewScrollView?.isHidden = false

        // Force immediate content load
        if editArea.markdownView != nil {
            showWebView()
        }

        // Load content in PPT mode
        refillEditArea()
        // Disable editor's find bar to prevent Cmd+F from being intercepted by NSTextView
        editArea.usesFindBar = false
        // Hide editor scrollbar to prevent overlap with preview scrollbar
        editAreaScroll.hasVerticalScroller = false
        editAreaScroll.hasHorizontalScroller = false
        DispatchQueue.main.async {
            vc.titiebarHeight.constant = 0.0
            vc.titleLabel.isHidden = true
            vc.titleBarView.isHidden = true
            vc.handlePPTAutoTransition()
        }
        if !UserDefaultsManagement.isOnExportPPT {
            DispatchQueue.main.asyncAfter(deadline: .now() + EditorTiming.presentationLayoutDelay) {
                vc.toast(message: I18n.str("🙊 Press ESC key to exit~"))
            }
        }
    }

    func handlePPTAutoTransition() {
        guard let vc = ViewController.shared() else { return }
        // Get cursor position and auto-navigate
        let range = editArea.selectedRange
        // If selectedIndex > editArea.string.count(), use string.count() value
        // If final calculation is negative, use 0
        let selectedIndex = max(min(range.location, editArea.string.count) - 1, 0)
        let beforeString = editArea.string[..<selectedIndex]
        let hrCount = beforeString.components(separatedBy: "---").count
        if UserDefaultsManagement.previewLocation == "Editing", hrCount > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + EditorTiming.pptSlideTransitionDelay) {
                // Auto-navigation in PPT mode
                vc.editArea.markdownView?.slideTo(index: hrCount - 1)
            }
        }
        // Compatible with keyboard shortcut passthrough
        DispatchQueue.main.asyncAfter(deadline: .now() + EditorTiming.pptFocusDelay) {
            NSApp.mainWindow?.makeFirstResponder(vc.editArea.markdownView)
        }
    }

    func disableMiaoYanPPT() {
        // Clear magicPPT flag FIRST to allow disablePreview to work properly
        UserDefaultsManagement.magicPPT = false

        // Update button states
        DispatchQueue.main.async {
            self.previewButton.state = .off
            self.previewButton.contentTintColor = nil
            self.presentationButton.state = .off
            self.presentationButton.contentTintColor = nil
        }
        // Restore title components that were hidden in PPT mode
        DispatchQueue.main.async {
            self.titleLabel.isHidden = false
            self.titleBarView.isHidden = false
            self.titiebarHeight.constant = 40.0
        }
        // Exit fullscreen if in fullscreen
        if UserDefaultsManagement.fullScreen {
            UserDefaultsManagement.fullScreen = false
            view.window?.toggleFullScreen(nil)
        }
        // Restore UI elements after fullscreen transition completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.restorePresentationLayout()
            self.disablePreview()
            self.updateButtonStates()
        }

        // Hide webview and return to text editor
        if editArea.markdownView != nil {
            hideWebView()
        }
        // Restore editor content and focus
        refillEditArea()
        DispatchQueue.main.async {
            self.titleLabel.isEditable = true
            self.focusEditArea()
        }
    }

    // MARK: - Text Formatting
    func formatText() {
        if UserDefaultsManagement.preview {
            toast(
                message: I18n.str("😶‍🌫 Format is only possible after exiting preview mode~")
            )
            return
        }
        // Prevent rapid successive formatting
        guard !isFormatting else {
            return
        }
        if let note = notesTableView.getSelectedNote() {
            isFormatting = true
            saveTitleSafely()
            let formatter = PrettierFormatter(plugins: [MarkdownPlugin()], parser: MarkdownParser())
            formatter.htmlWhitespaceSensitivity = HTMLWhitespaceSensitivityStrategy.ignore
            formatter.proseWrap = ProseWrapStrategy.preserve  // Change from .never to .preserve to keep line breaks
            formatter.prepare()
            // Get latest content from editor to ensure consistency
            let content = editArea.textStorage?.string ?? note.content.string
            let cursor = editArea.selectedRanges[0].rangeValue.location
            let top = editAreaScroll.contentView.bounds.origin.y
            let (protectedContent, htmlPlaceholders) = HtmlManager.protectHTMLTags(in: content)
            let adjustedCursor = HtmlManager.adjustCursorForProtectedContent(cursor: cursor, original: content, protected: protectedContent)
            let result = formatter.format(protectedContent, withCursorAtLocation: adjustedCursor)
            switch result {
            case .success(let formatResult):
                let restoredContent = HtmlManager.restoreHTMLTags(in: formatResult.formattedString, with: htmlPlaceholders)
                var newContent = restoredContent
                // Preserve line structure if Prettier removes line breaks
                let originalLines = content.components(separatedBy: .newlines)
                if originalLines.count > 1 && !restoredContent.contains("\n") {
                    newContent = content
                    for (_, originalTag) in htmlPlaceholders {
                        let updatedTag = originalTag
                        newContent = newContent.replacingOccurrences(of: originalTag, with: updatedTag)
                    }
                } else {
                    newContent = restoredContent
                    if content.last != "\n" && restoredContent.last == "\n" {
                        newContent = restoredContent.removeLastNewLine()
                    }
                }
                // Sync note.content with the current editor so state remains consistent
                if let currentStorage = editArea.textStorage {
                    note.content = NSMutableAttributedString(attributedString: currentStorage)
                }
                // Capture the original length before applying the update
                let originalLength = note.content.length
                // Replace the editor content so textStorage and note.content stay aligned
                editArea.insertText(newContent, replacementRange: NSRange(0..<originalLength))
                note.save()
                if let storage = editArea.textStorage {
                    NotesTextProcessor.highlightMarkdown(attributedString: storage, note: note)
                    storage.updateParagraphStyle()
                    editArea.fillHighlightLinks()
                    // Reapply letter spacing after formatting
                    storage.applyEditorLetterSpacing()
                }
                let adjustedCursorOffset = HtmlManager.adjustCursorAfterRestore(originalOffset: formatResult.cursorOffset, protected: protectedContent, restored: newContent)
                editArea.setSelectedRange(NSRange(location: adjustedCursorOffset, length: 0))
                formatContent = newContent

                // Restore scroll position after cursor is set to prevent auto-scroll
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.editAreaScroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: top))
                    self.editAreaScroll.reflectScrolledClipView(self.editAreaScroll.contentView)
                }
                toast(message: I18n.str("🎉 Automatic typesetting succeeded~"))

                // Trigger preview update if in Split View mode to re-render formulas and diagrams
                if UserDefaultsManagement.splitViewMode, let previewView = editArea.markdownView {
                    previewView.updateContent(note: note)
                }
            case .failure(let error):
                AppDelegate.trackError(error, context: "ViewController+Editor.format")
                toast(message: I18n.str("❌ Formatting failed, please try again"))
            }
            isFormatting = false
        }
    }

    // MARK: - WebView Management
    func getScrollTop() -> CGFloat {
        let contentHeight = editAreaScroll.contentSize.height
        let scrollTop = editAreaScroll.contentView.bounds.origin.y
        let scrollHeight = editAreaScroll.documentView!.bounds.height
        if scrollHeight - contentHeight > 0, scrollTop > 0 {
            return scrollTop / (scrollHeight - contentHeight)
        } else {
            return 0.0
        }
    }

    func preloadWebView() {
        guard editArea.markdownView == nil, !UserDefaultsManagement.preview else { return }
        guard let tempNote = makeTempNote() else { return }
        let frame = previewScrollView?.bounds ?? editArea.bounds
        let previewView = MPreviewView(frame: frame, note: tempNote, closure: {})
        previewView.autoresizingMask = [.width, .height]
        previewView.isHidden = true
        editArea.markdownView = previewView
        preparePreviewContainer(hidden: true)
    }

    @MainActor
    func preparePreviewContainer(hidden: Bool = false) {
        guard let previewScroll = previewScrollView else {
            return
        }

        if editArea.markdownView == nil {
            let frame = previewScroll.bounds
            let fallbackNote = notesTableView.getSelectedNote() ?? makeTempNote()
            guard let note = fallbackNote else {
                return
            }
            let markdownView = MPreviewView(frame: frame, note: note, closure: {})
            markdownView.autoresizingMask = [.width, .height]
            editArea.markdownView = markdownView
        }

        guard let markdownView = editArea.markdownView else {
            return
        }
        markdownView.removeFromSuperview()
        markdownView.frame = previewScroll.bounds
        markdownView.autoresizingMask = [.width, .height]
        markdownView.isHidden = hidden
        // Alpha is managed by enablePreview/fill to support Soft Reveal
        // if !hidden { markdownView.alphaValue = 1.0 }
        previewScroll.documentView = markdownView
        previewScroll.isHidden = hidden
    }

    private func startSplitScrollSync() {
        guard UserDefaultsManagement.splitViewMode,
            splitScrollObserver == nil,
            let editorClip = editAreaScroll?.contentView as? NSClipView
        else {
            return
        }

        editorClip.postsBoundsChangedNotifications = true

        // Monitor editor scrolling
        splitScrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: editorClip,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleSplitScrollEvent()
            }
        }

        // Monitor preview (WebView) scrolling via delegate
        if let markdownView = editArea.markdownView {
            markdownView.scrollDelegate = self
        }

        scheduleSplitScrollSync()
    }

    private func stopSplitScrollSync() {
        if let observer = splitScrollObserver {
            NotificationCenter.default.removeObserver(observer)
            splitScrollObserver = nil
        }
        // Clear preview scroll delegate
        editArea.markdownView?.scrollDelegate = nil
        // Cancel any pending sync
        splitScrollDebounceTimer?.invalidate()
        splitScrollDebounceTimer = nil
        isProgrammaticSplitScroll = false
        lastSyncedScrollRatio = -1  // Reset for next sync session
    }

    private func handleSplitScrollEvent() {
        guard !isProgrammaticSplitScroll else { return }
        // Skip scroll sync if preview is updating content
        guard editArea.markdownView?.isUpdatingContent != true else {
            return
        }
        // Use debounce instead of blocking to ensure all user scrolls (including typing) are synced
        scheduleSplitScrollSync()
    }

    // MARK: - MPreviewScrollDelegate

    func previewDidScroll(ratio: CGFloat) {
        handlePreviewScroll(ratio: ratio)
    }

    private func handlePreviewScroll(ratio: CGFloat) {
        // Skip scroll sync if preview is updating content
        guard !isProgrammaticSplitScroll,
            UserDefaultsManagement.splitViewMode,
            editArea.markdownView?.isUpdatingContent != true
        else {
            return
        }

        isProgrammaticSplitScroll = true
        scrollEditor(to: ratio)

        // Immediate reset for faster response (scroll events are already debounced in JS)
        DispatchQueue.main.async { [weak self] in
            self?.isProgrammaticSplitScroll = false
        }
    }

    private func scheduleSplitScrollSync() {
        guard UserDefaultsManagement.splitViewMode else { return }

        let ratio = editorScrollRatio()
        let clampedRatio = max(0, min(ratio, 1))

        // Performance optimization: Only sync if ratio changed significantly (> 0.5% difference)
        // This reduces JavaScript execution by 70-80% during scrolling
        if abs(clampedRatio - lastSyncedScrollRatio) > SplitScrollConfig.syncThreshold {
            lastSyncedScrollRatio = clampedRatio
            applySplitScrollSync(ratio: clampedRatio)
        }
    }

    private func applySplitScrollSync(ratio: CGFloat) {
        guard UserDefaultsManagement.splitViewMode else { return }
        isProgrammaticSplitScroll = true
        // Editor scrolled -> sync to preview
        editArea.markdownView?.scrollToPosition(pre: ratio)
        // Reset after JS requestAnimationFrame completes
        DispatchQueue.main.asyncAfter(deadline: .now() + EditorTiming.splitScrollSyncDelay) { [weak self] in
            self?.isProgrammaticSplitScroll = false
        }
    }

    private func editorScrollRatio() -> CGFloat {
        getScrollTop()
    }

    private func scrollEditor(to ratio: CGFloat) {
        guard let documentView = editAreaScroll.documentView else {
            return
        }
        let contentHeight = editAreaScroll.contentSize.height
        let scrollHeight = documentView.bounds.height
        let offset = max(scrollHeight - contentHeight, 0)

        guard offset > 0 else {
            return
        }

        let targetY = offset * ratio
        let currentY = editAreaScroll.contentView.bounds.origin.y

        // Only scroll if there's a meaningful difference (> 0.5 pixels)
        guard abs(targetY - currentY) > SplitScrollConfig.scrollDifferenceThreshold else {
            return
        }

        // Direct scroll for instant response
        let newOrigin = NSPoint(x: 0, y: targetY)
        editAreaScroll.contentView.setBoundsOrigin(newOrigin)
        editAreaScroll.reflectScrolledClipView(editAreaScroll.contentView)
    }

    func cancelTextSearch() {
        if UserDefaultsManagement.preview || UserDefaultsManagement.presentation || UserDefaultsManagement.magicPPT {
            editArea.markdownView?.hideSearchBar()
        } else {
            editArea.hideSearchBar()
        }
        NSApp.mainWindow?.makeFirstResponder(editArea)
    }

    @IBAction func togglePreview(_ sender: NSButton) {
        togglePreview()
    }

    @IBAction func togglePresentation(_ sender: NSButton) {
        togglePresentation()
    }

    @IBAction func toggleMagicPPT(_ sender: Any) {
        saveTitleSafely()
        if UserDefaultsManagement.magicPPT {
            disableMiaoYanPPT()
        } else {
            if !isMiaoYanPPT() {
                return
            }
            enableMiaoYanPPT()
        }
    }

    @IBAction func formatText(_ sender: NSButton) {
        formatText()
    }

    // MARK: - Editor Focus Management
    func focusEditArea(firstResponder: NSResponder? = nil, restoreCursor: Bool = true) {
        guard EditTextView.note != nil else { return }
        var resp: NSResponder = editArea
        if let responder = firstResponder {
            resp = responder
        }
        if notesTableView.selectedRow > -1 {
            DispatchQueue.main.async {
                self.editArea.isEditable = true
                // Only show title bar if not in PPT mode
                if !UserDefaultsManagement.magicPPT {
                    self.titleBarView.isHidden = false
                }
                self.editArea.window?.makeFirstResponder(resp)
                if restoreCursor {
                    self.editArea.restoreCursorPosition()
                }
            }
            return
        }
        editArea.window?.makeFirstResponder(resp)
    }

    func focusTable() {
        DispatchQueue.main.async {
            let index = self.notesTableView.selectedRow > -1 ? self.notesTableView.selectedRow : 0
            self.notesTableView.window?.makeFirstResponder(self.notesTableView)
            self.notesTableView.selectRowIndexes([index], byExtendingSelection: false)
            self.notesTableView.scrollRowToVisible(row: index, animated: true)
        }
    }

    // MARK: - Editor Content Management
    func refillEditArea(
        cursor: Int? = nil,
        previewOnly: Bool = false,
        saveTyping: Bool = false,
        force: Bool = false,
        animatePreview: Bool = true,
        suppressSave: Bool = false
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.updateToolbarButtonTints()
        }
        // Allow content refill in these scenarios:
        // - Normal refill (not preview-only), or
        // - Preview-only refill when in any preview/presentation mode (including split view mode), or
        // - Force refill regardless of conditions
        // Note: Split view mode needs preview refill to update the preview pane content
        guard force || !previewOnly || (previewOnly && shouldShowPreview) else {
            return
        }

        // Fix race condition: Cancel any pending table selection updates to prevent them from interfering with this refill
        notesTableView.loadingQueue.cancelAllOperations()

        DispatchQueue.main.async {
            let now = ProcessInfo.processInfo.systemUptime
            let isRapidPreviewSwitch = self.shouldShowPreview && (now - self.lastPreviewReloadTime) < 0.2
            if self.shouldShowPreview {
                self.lastPreviewReloadTime = now
            }
            var location: Int = 0
            if let unwrappedCursor = cursor {
                location = unwrappedCursor
            } else {
                location = self.editArea.selectedRanges[0].rangeValue.location
            }
            let selected = self.notesTableView.selectedRow
            if selected > -1, self.notesTableView.noteList.indices.contains(selected) {
                if let note = self.notesTableView.getSelectedNote() {
                    // Safety: Ensure current editor content is saved to note before reloading
                    // This prevents data loss during rapid view switching where the editor might be dirty
                    let shouldPersistEditor = !self.shouldShowPreview || UserDefaultsManagement.splitViewMode
                    if shouldPersistEditor,
                        let currentNote = EditTextView.note,
                        currentNote === note,
                        force || !previewOnly
                    {
                        if !suppressSave {
                            // SAFETY CHECK: Prevent overwriting content with empty string during view mode toggle
                            // This catches the specific data loss case where editor content is lost but note exists
                            if self.editArea.string.isEmpty && currentNote.content.length > 0 {
                                self.internalLogDebug("Skipping save of empty content to non-empty note: \(currentNote.getFileName())")
                            } else {
                                self.editArea.saveTextStorageContent(to: currentNote)
                                // CRITICAL: Mark content as loaded to prevent ensureContentLoaded() from reloading stale disk content
                                // This fixes content loss when rapidly toggling split view before auto-save completes
                                currentNote.markContentAsLoaded()
                            }
                        }
                    }

                    let options = FillOptions(
                        highlight: true,
                        saveTyping: saveTyping,
                        force: force,
                        needScrollToCursor: true,
                        previewOnly: previewOnly,
                        animatePreview: animatePreview && !isRapidPreviewSwitch,
                        preserveUndo: true  // Preserve undo stack during view refreshes (e.g. Split View toggle)
                    )
                    self.editArea.fill(note: note, options: options)
                    self.editArea.setSelectedRange(NSRange(location: location, length: 0))
                }
            }
        }
    }

    public func updateTitle(newTitle: String) {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "MiaoYan"
        var title = newTitle

        if newTitle.isValidUUID {
            title = String()
        }

        // Temporarily disable title change tracking to avoid overwriting pending changes
        UserDataService.instance.isUpdatingTitle = true
        titleLabel.setStringValueSafely(title)
        UserDataService.instance.isUpdatingTitle = false
        titleLabel.currentEditor()?.selectedRange = NSRange(location: title.utf16.count, length: 0)
        MainWindowController.shared()?.title = appName
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField, textField == titleLabel else {
            return
        }

        // Don't track changes during programmatic updates
        guard !UserDataService.instance.isUpdatingTitle else {
            return
        }

        // Store the current edited title and the note it belongs to for later use
        if let currentNote = EditTextView.note {
            let currentTitle = titleLabel.stringValue.trimmingCharacters(in: NSCharacterSet.newlines)
            UserDataService.instance.pendingTitleChange = (title: currentTitle, note: currentNote)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField, textField == titleLabel else {
            return
        }

        if shouldProcess() {
            saveTitleSafely()
            restoreFocus()
            // Clear pending change since we processed it
            UserDataService.instance.pendingTitleChange = nil
        } else {
            refreshTitle()
            // Keep pending change for handleSelectionChange to process
        }
    }

    private func shouldProcess() -> Bool {
        return titleLabel.isEditable && titleLabel.hasFocus()
    }

    private func restoreFocus() {
        if let responder = titleLabel.restoreResponder {
            view.window?.makeFirstResponder(responder)
            titleLabel.restoreResponder = nil
        } else {
            view.window?.makeFirstResponder(notesTableView)
        }
    }

    private func refreshTitle() {
        guard let note = notesTableView.getSelectedNote() else { return }
        let title = note.getTitleWithoutLabel()
        updateTitle(newTitle: title)
    }

    func saveTitleSafely() {
        let targetNote: Note?
        let titleToSave: String

        if let pendingChange = UserDataService.instance.pendingTitleChange {
            // Use tracked changes to save to the correct note
            targetNote = pendingChange.note
            titleToSave = pendingChange.title
        } else {
            // Fall back to selected note with safety check
            targetNote = notesTableView.getSelectedNote()
            titleToSave = clean(titleLabel.stringValue)

            // Ensure title matches the selected note to prevent data corruption
            if let note = targetNote {
                let currentNoteTitle = note.getTitleWithoutLabel()
                if titleToSave != currentNoteTitle {
                    return  // Skip save if title doesn't match note
                }
            }
        }

        guard let note = targetNote else { return }

        let newTitle = titleToSave.trimmingCharacters(in: NSCharacterSet.newlines)
        guard !newTitle.isEmpty else { return }

        let currentName = note.getFileName()
        guard currentName != newTitle else { return }

        let result = attemptSave(note: note, title: newTitle, current: currentName)
        handleResult(result, title: newTitle, note: note)
    }

    public func saveTitle(_ title: String, to note: Note) {
        let newTitle = title.trimmingCharacters(in: NSCharacterSet.newlines)
        guard !newTitle.isEmpty else { return }

        let currentName = note.getFileName()
        guard currentName != newTitle else { return }

        let result = attemptSave(note: note, title: newTitle, current: currentName)
        if case .success = result {
            note.title = newTitle
            notesTableView.reloadRow(note: note)
        }
    }

    private func clean(_ title: String) -> String {
        return title.trimmingCharacters(in: NSCharacterSet.newlines)
    }

    private func attemptSave(note: Note, title: String, current: String) -> SaveResult {
        let fileName = cleanFileName(title)
        let dst = note.project.url.appendingPathComponent(fileName).appendingPathExtension(note.url.pathExtension)
        let isCaseChange = current.lowercased() == title.lowercased() && current != title

        if (!FileManager.default.fileExists(atPath: dst.path) || isCaseChange) && note.move(to: dst) {
            note.title = title
            return .success
        } else {
            return .exists
        }
    }

    private func cleanFileName(_ name: String) -> String {
        return
            name
            .trimmingCharacters(in: CharacterSet.whitespaces)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: ":")
    }

    private func handleResult(_ result: SaveResult, title: String, note: Note) {
        switch result {
        case .success:
            updateTitle(newTitle: title)
            notesTableView.reloadRow(note: note)
            titleLabel.isEditable = true
        case .exists:
            updateTitle(newTitle: title)
            titleLabel.resignFirstResponder()
            showAlert(for: title)
        }
    }

    private func showAlert(for title: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.informativeText = String(format: I18n.str("This %@ under this folder already exists!"), title)
        alert.messageText = I18n.str("Please change the title")
        alert.runModal()
    }

    private enum SaveResult {
        case success
        case exists
    }
}
