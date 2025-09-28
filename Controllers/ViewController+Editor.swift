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
        if let webView = editArea.markdownView {
            webView.alphaValue = 0.0
            webView.isHidden = false
            refillEditArea()
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
        if let webView = editArea.markdownView {
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    webView.animator().alphaValue = 0.0
                },
                completionHandler: { [weak webView] in
                    Task { @MainActor in
                        webView?.isHidden = true
                        webView?.alphaValue = 1.0
                        webView?.loadHTMLString("<html><body style='background:transparent;'></body></html>", baseURL: nil)
                    }
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
        saveTitleSafely()
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
                self.toast(message: I18n.str("🙊 Press ESC key to exit~"))
            }
        }
    }

    func disablePresentation() {
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
                vc.toast(message: I18n.str("🙊 Press ESC key to exit~"))
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
                completionHandler: { [weak webView] in
                    Task { @MainActor in
                        webView?.isHidden = true
                        webView?.alphaValue = 1.0
                    }
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
                    editArea.fillHighlightLinks()
                    // Reapply letter spacing after formatting
                    storage.applyEditorLetterSpacing()
                }
                let adjustedCursorOffset = HtmlManager.adjustCursorAfterRestore(originalOffset: formatResult.cursorOffset, protected: protectedContent, restored: newContent)
                editArea.setSelectedRange(NSRange(location: adjustedCursorOffset, length: 0))
                editAreaScroll.documentView?.scroll(NSPoint(x: 0, y: top))
                formatContent = newContent
                toast(message: I18n.str("🎉 Automatic typesetting succeeded~"))
            case .failure(let error):
                AppDelegate.trackError(error, context: "ViewController+Editor.format")
                toast(message: I18n.str("❌ Formatting failed, please try again"))
            }
            TelemetryDeck.signal("Editor.Format")
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

    func cancelTextSearch() {
        let menu = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.tag = NSTextFinder.Action.hideFindInterface.rawValue
        editArea.performTextFinderAction(menu)
        if !UserDefaultsManagement.preview {
            NSApp.mainWindow?.makeFirstResponder(editArea)
        }
    }

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
                    let options = FillOptions(
                        highlight: true,
                        saveTyping: saveTyping,
                        force: force,
                        needScrollToCursor: true
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

    private func saveTitleSafely() {
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
