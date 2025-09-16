import Cocoa
import Foundation
import Prettier
import PrettierMarkdown
import TelemetryDeck

// MARK: - Editor Management
extension ViewController {
    // MARK: - Preview Management
    func enablePreview() {
        if !UserDefaultsManagement.magicPPT {
            UserDefaultsManagement.preview = true
        }
        isFocusedTitle = titleLabel.hasFocus()
        cancelTextSearch()
        editArea.window?.makeFirstResponder(notesTableView)
        // Keep WebView alive: hide first, then show with animation after content update
        if let webView = editArea.markdownView {
            webView.alphaValue = 0.0
            webView.isHidden = false
            // Update content first, then show animation
            refillEditArea()
            // Brief delay to ensure content loads before showing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    webView.animator().alphaValue = 1.0
                })
            }
        } else {
            refillEditArea()
        }
        titleLabel.isEditable = false
        if UserDefaultsManagement.previewLocation == "Editing", !UserDefaultsManagement.isOnExport {
            let scrollPre = getScrollTop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.editArea.markdownView?.scrollToPosition(pre: scrollPre)
            }
        }
    }
    func disablePreview() {
        if UserDefaultsManagement.magicPPT {
            return
        }
        if UserDefaultsManagement.currentEditorMode == .preview {
            UserDefaultsManagement.magicPPT = false
        }
        // Keep WebView alive: hide and clear content
        if let webView = editArea.markdownView {
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    webView.animator().alphaValue = 0.0
                },
                completionHandler: {
                    webView.isHidden = true
                    webView.alphaValue = 1.0
                    webView.loadHTMLString("<html><body style='background:transparent;'></body></html>", baseURL: nil)
                })
        }
        refillEditArea()
        DispatchQueue.main.async {
            self.titleLabel.isEditable = true
        }
        if !isFocusedTitle {
            focusEditArea()
        }
    }
    func togglePreview() {
        titleLabel.saveTitle()
        if UserDefaultsManagement.preview {
            disablePreview()
        } else {
            enablePreview()
            TelemetryDeck.signal("Editor.Preview")
        }
    }
    // MARK: - Presentation Mode
    func enablePresentation() {
        UserDefaultsManagement.presentation = true
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
        hideNoteList("")
        formatButton.isHidden = true
        previewButton.isHidden = true
        // Show preview content without changing global preview mode
        // Maintains presentation state to prevent mode conflicts
        if editArea.markdownView == nil {
            refillEditArea(previewOnly: true, force: true)
        } else {
            editArea.markdownView?.alphaValue = 0.0
            editArea.markdownView?.isHidden = false
            refillEditArea(previewOnly: true, force: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.editArea.markdownView?.animator().alphaValue = 1.0
                })
            }
        }
        presentationButton.state = .on
        if !UserDefaultsManagement.fullScreen {
            view.window?.toggleFullScreen(nil)
        }
        if !UserDefaultsManagement.isOnExportPPT {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.toast(message: NSLocalizedString("🙊 Press ESC key to exit~", comment: ""))
            }
        }
    }
    func disablePresentation() {
        // Defer presentation flag update until UI is fully restored to prevent state conflicts
        presentationButton.state = .off
        if UserDefaultsManagement.fullScreen {
            UserDefaultsManagement.fullScreen = false
            view.window?.toggleFullScreen(nil)
        }
        // Restore UI elements after fullscreen transition completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Restore UI elements
            self.formatButton.isHidden = false
            self.previewButton.isHidden = false
            // Restore layout
            // Always restore three-panel layout when exiting presentation mode
            self.showNoteList("")
            if self.sidebarWidth == 0 { self.showSidebar("") }
            self.checkTitlebarTopConstraint()
            // Restore scroll position
            if let savedPosition = self.savedPresentationScrollPosition,
                let clipView = self.notesTableView.superview as? NSClipView
            {
                clipView.setBoundsOrigin(savedPosition)
                self.savedPresentationScrollPosition = nil
            }
            // Force return to editing mode and update state flags
            self.disablePreview()
            // Safely update presentation state after UI restoration
            UserDefaultsManagement.presentation = false
            self.updateButtonStates()
        }
    }

    // MARK: - Helper Methods
    private func updateButtonStates() {
        DispatchQueue.main.async {
            self.previewButton.state = UserDefaultsManagement.preview ? .on : .off
            self.presentationButton.state = UserDefaultsManagement.presentation ? .on : .off
        }
    }

    func togglePresentation() {
        titleLabel.saveTitle()
        // Handle both presentation and PPT modes
        if UserDefaultsManagement.presentation || UserDefaultsManagement.magicPPT {
            if UserDefaultsManagement.magicPPT {
                disableMiaoYanPPT()
            } else {
                disablePresentation()
            }
        } else {
            enablePresentation()
            TelemetryDeck.signal("Editor.Presentation")
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
            toast(message: NSLocalizedString("😶‍🌫 No delimiter --- identification, Cannot use MiaoYan PPT~", comment: ""))
        }
        return false
    }
    func toggleMagicPPT() {
        titleLabel.saveTitle()
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
        // Set PPT mode directly - this handles all state properly
        UserDefaultsManagement.magicPPT = true
        // Save current layout state before entering PPT mode
        let currentSidebarWidth = sidebarWidth
        let currentNotelistWidth = notelistWidth
        // Force save current sidebar width
        if currentSidebarWidth > 86 {
            UserDefaultsManagement.realSidebarSize = Int(currentSidebarWidth)
        }
        // Force save current notelist width
        if currentNotelistWidth > 0 {
            UserDefaultsManagement.sidebarSize = Int(currentNotelistWidth)
        }
        // Save current notelist scroll position
        if let clipView = notesTableView.superview as? NSClipView {
            savedPresentationScrollPosition = clipView.bounds.origin
        }
        // Hide UI elements for PPT mode
        hideNoteList("")
        formatButton.isHidden = true
        previewButton.isHidden = true
        // Update button states to reflect PPT mode
        DispatchQueue.main.async {
            vc.previewButton.state = .on
            vc.presentationButton.state = .on
        }
        // Enable fullscreen for PPT
        if !UserDefaultsManagement.fullScreen {
            view.window?.toggleFullScreen(nil)
        }
        // Ensure we have preview content
        if editArea.markdownView == nil {
            refillEditArea()
        } else {
            // Show existing webview with animation
            editArea.markdownView?.alphaValue = 0.0
            editArea.markdownView?.isHidden = false
            refillEditArea()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    vc.editArea.markdownView?.animator().alphaValue = 1.0
                })
            }
        }
        // Adjust title bar for cleaner PPT experience
        DispatchQueue.main.async {
            vc.titiebarHeight.constant = 0.0
            vc.titleLabel.isHidden = true
            vc.titleBarView.isHidden = true
            vc.handlePPTAutoTransition()
        }
        if !UserDefaultsManagement.isOnExportPPT {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                vc.toast(message: NSLocalizedString("🙊 Press ESC key to exit~", comment: ""))
            }
        }
        TelemetryDeck.signal("Editor.PPT")
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // Auto-navigation in PPT mode
                vc.editArea.markdownView?.slideTo(index: hrCount - 1)
            }
        }
        // Compatible with keyboard shortcut passthrough
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSApp.mainWindow?.makeFirstResponder(vc.editArea.markdownView)
        }
    }
    func disableMiaoYanPPT() {
        // Defer magicPPT flag update until UI fully restored to prevent conflicts
        DispatchQueue.main.async {
            self.previewButton.state = .off
            self.presentationButton.state = .off
        }
        // Restore title components that were hidden in PPT mode
        DispatchQueue.main.async {
            self.titleLabel.isHidden = false
            self.titleBarView.isHidden = false
            self.titiebarHeight.constant = 40.0  // Restore title bar height
        }
        // Exit fullscreen if in fullscreen
        if UserDefaultsManagement.fullScreen {
            UserDefaultsManagement.fullScreen = false
            view.window?.toggleFullScreen(nil)
        }
        // Restore UI elements after fullscreen transition completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Show hidden UI elements
            self.formatButton.isHidden = false
            self.previewButton.isHidden = false
            // Always restore three-panel layout when exiting PPT mode
            self.showNoteList("")
            if self.sidebarWidth == 0 { self.showSidebar("") }
            self.checkTitlebarTopConstraint()
            // Restore scroll position
            if let savedPosition = self.savedPresentationScrollPosition,
                let clipView = self.notesTableView.superview as? NSClipView
            {
                clipView.setBoundsOrigin(savedPosition)
                self.savedPresentationScrollPosition = nil
            }
            // Force return to editing mode and update state flags
            self.disablePreview()
            // Safely update magicPPT state after UI restoration
            UserDefaultsManagement.magicPPT = false
            self.updateButtonStates()
        }

        // Hide webview and return to text editor
        if let webView = editArea.markdownView {
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    webView.animator().alphaValue = 0.0
                },
                completionHandler: {
                    webView.isHidden = true
                    webView.alphaValue = 1.0
                })
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
                message: NSLocalizedString("😶‍🌫 Format is only possible after exiting preview mode~", comment: "")
            )
            return
        }
        // 防止快速连续格式化
        guard !isFormatting else {
            return
        }
        if let note = notesTableView.getSelectedNote() {
            // 设置格式化状态
            isFormatting = true
            // Save title first to prevent first-time issues
            titleLabel.saveTitle()
            let formatter = PrettierFormatter(plugins: [MarkdownPlugin()], parser: MarkdownParser())
            formatter.htmlWhitespaceSensitivity = HTMLWhitespaceSensitivityStrategy.ignore
            formatter.proseWrap = ProseWrapStrategy.preserve  // Change from .never to .preserve to keep line breaks
            formatter.prepare()
            // 确保从编辑器获取最新内容，而不是从 note.content，避免状态不一致
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
                // Simple approach: if Prettier changed the line structure,
                // only update the HTML tags and preserve everything else
                let originalLines = content.components(separatedBy: .newlines)
                if originalLines.count > 1 && !restoredContent.contains("\n") {
                    // Prettier removed line breaks, restore original structure but update HTML
                    newContent = content
                    // Only replace HTML tags with formatted versions
                    for (_, originalTag) in htmlPlaceholders {
                        let updatedTag = originalTag  // Keep original HTML tag as-is
                        newContent = newContent.replacingOccurrences(of: originalTag, with: updatedTag)
                    }
                } else {
                    // Normal case: use formatted content
                    newContent = restoredContent
                    if content.last != "\n" && restoredContent.last == "\n" {
                        newContent = restoredContent.removeLastNewLine()
                    }
                }
                // 同步 note.content 与当前编辑器内容，确保状态一致
                if let currentStorage = editArea.textStorage {
                    note.content = NSMutableAttributedString(attributedString: currentStorage)
                }
                // 计算原始内容长度（在更新前）
                let originalLength = note.content.length
                // 直接更新编辑器显示，这会同时更新 textStorage 和 note.content
                editArea.insertText(newContent, replacementRange: NSRange(0..<originalLength))
                // 保存到文件
                note.save()
                // 重新应用 Markdown 语法高亮
                if let storage = editArea.textStorage {
                    NotesTextProcessor.highlightMarkdown(attributedString: storage, note: note)
                    editArea.fillHighlightLinks()
                    // Reapply letter spacing after formatting
                    storage.applyEditorLetterSpacing()
                }
                let adjustedCursorOffset = HtmlManager.adjustCursorAfterRestore(originalOffset: formatResult.cursorOffset, protected: protectedContent, restored: newContent)
                editArea.setSelectedRange(NSRange(location: adjustedCursorOffset, length: 0))
                editAreaScroll.documentView?.scroll(NSPoint(x: 0, y: top))
                formatContent = newContent
                toast(message: NSLocalizedString("🎉 Automatic typesetting succeeded~", comment: ""))
            case .failure(let error):
                AppDelegate.trackError(error, context: "ViewController+Editor.format")
                toast(message: NSLocalizedString("❌ Formatting failed, please try again", comment: ""))
            }
            TelemetryDeck.signal("Editor.Format")
            // 重置格式化状态（无论成功或失败）
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
        let tempProject = getSidebarProject() ?? storage.noteList.first?.project
        guard let project = tempProject else { return }
        let tempNote = Note(name: "", project: project, type: .markdown)
        tempNote.content = NSMutableAttributedString(string: "")
        let frame = editArea.bounds
        editArea.markdownView = MPreviewView(frame: frame, note: tempNote, closure: {})
        editArea.markdownView?.isHidden = true
        if let view = editArea.markdownView {
            editAreaScroll.addSubview(view)
        }
    }
    // MARK: - Text Search
    func cancelTextSearch() {
        let menu = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.tag = NSTextFinder.Action.hideFindInterface.rawValue
        editArea.performTextFinderAction(menu)
        if !UserDefaultsManagement.preview {
            NSApp.mainWindow?.makeFirstResponder(editArea)
        }
    }
    // MARK: - IBActions
    @IBAction func togglePreview(_ sender: NSButton) {
        togglePreview()
    }
    @IBAction func togglePresentation(_ sender: NSButton) {
        togglePresentation()
    }
    @IBAction func toggleMagicPPT(_ sender: Any) {
        toggleMagicPPT()
    }
    @IBAction func formatText(_ sender: NSButton) {
        formatText()
    }
    // MARK: - Editor Focus Management
    func focusEditArea(firstResponder: NSResponder? = nil) {
        guard EditTextView.note != nil else { return }
        var resp: NSResponder = editArea
        if let responder = firstResponder {
            resp = responder
        }
        if notesTableView.selectedRow > -1 {
            DispatchQueue.main.async {
                self.editArea.isEditable = true
                self.emptyEditAreaView.isHidden = true
                // Only show title bar if not in PPT mode
                if !UserDefaultsManagement.magicPPT {
                    self.titleBarView.isHidden = false
                }
                self.editArea.window?.makeFirstResponder(resp)
                self.editArea.restoreCursorPosition()
            }
            return
        }
        editArea.window?.makeFirstResponder(resp)
    }
    func focusTable() {
        DispatchQueue.main.async {
            let index = self.notesTableView.selectedRow > -1 ? self.notesTableView.selectedRow : 0
            self.notesTableView.window?.makeFirstResponder(self.notesTableView)
            self.notesTableView.selectRowIndexes([index], byExtendingSelection: true)
            self.notesTableView.scrollRowToVisible(row: index, animated: true)
        }
    }
    // MARK: - Editor Content Management
    func refillEditArea(cursor: Int? = nil, previewOnly: Bool = false, saveTyping: Bool = false, force: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            self?.previewButton.state = UserDefaultsManagement.preview ? .on : .off
            self?.presentationButton.state = UserDefaultsManagement.presentation ? .on : .off
        }
        // Allow content refill in these scenarios:
        // - Normal refill (not preview-only), or
        // - Preview-only refill when in any preview/presentation mode, or
        // - Force refill regardless of conditions
        guard force || !previewOnly || (previewOnly && (UserDefaultsManagement.preview || UserDefaultsManagement.magicPPT || UserDefaultsManagement.presentation)) else {
            return
        }
        DispatchQueue.main.async {
            var location: Int = 0
            if let unwrappedCursor = cursor {
                location = unwrappedCursor
            } else {
                location = self.editArea.selectedRanges[0].rangeValue.location
            }
            let selected = self.notesTableView.selectedRow
            if selected > -1, self.notesTableView.noteList.indices.contains(selected) {
                if let note = self.notesTableView.getSelectedNote() {
                    self.editArea.fill(note: note, highlight: true, saveTyping: saveTyping, force: force)
                    self.editArea.setSelectedRange(NSRange(location: location, length: 0))
                }
            }
        }
    }
    // MARK: - Title Management Override (fix for title disappearing issue)
    public func updateTitle(newTitle: String) {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "MiaoYan"
        var titleString = newTitle
        if newTitle.isValidUUID {
            titleString = String()
        }
        titleLabel.stringValue = titleString
        titleLabel.currentEditor()?.selectedRange = NSRange(location: titleString.utf16.count, length: 0)
        MainWindowController.shared()?.title = appName
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField, textField == titleLabel else {
            return
        }
        if titleLabel.isEditable == true {
            fileName(titleLabel)
            if let restoreResponder = titleLabel.restoreResponder {
                view.window?.makeFirstResponder(restoreResponder)
                titleLabel.restoreResponder = nil
            } else {
                view.window?.makeFirstResponder(notesTableView)
            }
        } else {
            let currentNote = notesTableView.getSelectedNote()
            updateTitle(newTitle: currentNote?.getTitleWithoutLabel() ?? NSLocalizedString("Untitled Note", comment: "Untitled Note"))
        }
    }
}

