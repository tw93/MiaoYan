import AppCenterAnalytics
import Cocoa
import Foundation
import Prettier
import PrettierMarkdown

// MARK: - Editor Management
extension ViewController {

    // MARK: - Preview Management

    func enablePreview() {
        isFocusedTitle = titleLabel.hasFocus()
        cancelTextSearch()
        editArea.window?.makeFirstResponder(notesTableView)
        UserDefaultsManagement.preview = true

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
        UserDefaultsManagement.preview = false
        UserDefaultsManagement.magicPPT = false
        UserDefaultsManagement.presentation = false

        // Keep WebView alive: hide and clear content
        if let webView = editArea.markdownView {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                webView.animator().alphaValue = 0.0
            }) {
                webView.isHidden = true
                webView.alphaValue = 1.0
                // Clear content to avoid remnants on next display
                webView.loadHTMLString("<html><body style='background:transparent;'></body></html>", baseURL: nil)
            }
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
            Analytics.trackEvent("MiaoYan Preview")
        }
    }

    // MARK: - Presentation Mode

    func enablePresentation() {
        // Save current layout state before entering presentation
        let currentSidebarWidth = sidebarWidth
        let currentNotelistWidth = notelistWidth

        // Force save current sidebar width - ensure it's always saved correctly
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

        // Hide UI elements (this will call hideSidebar but won't overwrite our saved values)
        hideNoteList("")
        formatButton.isHidden = true
        previewButton.isHidden = true

        // Set presentation state
        UserDefaultsManagement.presentation = true
        presentationButton.state = .on

        // Always enable preview for presentation
        if !UserDefaultsManagement.preview {
            enablePreview()
        }

        // Enter fullscreen
        if !UserDefaultsManagement.fullScreen {
            view.window?.toggleFullScreen(nil)
        }

        if !UserDefaultsManagement.isOnExportPPT {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.toast(message: NSLocalizedString("🙊 Press ESC key to exit~", comment: ""))
            }
        }
    }

    func disablePresentation() {
        // Step 1: Clear all states immediately
        UserDefaultsManagement.presentation = false
        UserDefaultsManagement.magicPPT = false
        presentationButton.state = .off

        // Step 2: Exit fullscreen first (if in fullscreen)
        if UserDefaultsManagement.fullScreen {
            UserDefaultsManagement.fullScreen = false
            view.window?.toggleFullScreen(nil)
        }

        // Step 3: Disable preview and switch to editor
        if UserDefaultsManagement.preview {
            disablePreview()
        }

        // Step 4: Restore UI elements after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Restore UI elements
            self.formatButton.isHidden = false
            self.previewButton.isHidden = false

            // Restore layout
            if UserDefaultsManagement.sidebarSize > 0 {
                self.showNoteList("")
            }

            if UserDefaultsManagement.realSidebarSize > 0 && self.sidebarWidth == 0 {
                self.showSidebar("")
            }

            self.checkTitlebarTopConstraint()

            // Restore scroll position
            if let savedPosition = self.savedPresentationScrollPosition,
                let clipView = self.notesTableView.superview as? NSClipView
            {
                clipView.setBoundsOrigin(savedPosition)
                self.savedPresentationScrollPosition = nil
            }
        }
    }

    func togglePresentation() {
        titleLabel.saveTitle()
        if UserDefaultsManagement.presentation {
            disablePresentation()
        } else {
            enablePresentation()
            Analytics.trackEvent("MiaoYan Presentation")
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
        if !isMiaoYanPPT() {
            return
        }
        if UserDefaultsManagement.magicPPT {
            disableMiaoYanPPT()
        } else {
            enableMiaoYanPPT()
        }
    }

    func enableMiaoYanPPT() {
        guard let vc = ViewController.shared() else { return }

        // Set PPT mode flag
        UserDefaultsManagement.magicPPT = true

        // Enable presentation
        vc.enablePresentation()

        // Adjust title bar
        DispatchQueue.main.async {
            vc.titiebarHeight.constant = 0.0
            vc.handlePPTAutoTransition()
        }

        Analytics.trackEvent("MiaoYan PPT")
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
        disablePresentation()
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
                        let updatedTag = originalTag // Keep original HTML tag as-is
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
                }
                
                let adjustedCursorOffset = HtmlManager.adjustCursorAfterRestore(originalOffset: formatResult.cursorOffset, protected: protectedContent, restored: newContent)
                
                editArea.setSelectedRange(NSRange(location: adjustedCursorOffset, length: 0))
                editAreaScroll.documentView?.scroll(NSPoint(x: 0, y: top))
                formatContent = newContent
                toast(message: NSLocalizedString("🎉 Automatic typesetting succeeded~", comment: ""))
                
            case .failure(let error):
                print("Format error: \(error)")
                toast(message: NSLocalizedString("❌ Formatting failed, please try again", comment: ""))
            }
            
            Analytics.trackEvent("MiaoYan Format")
            
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

        let tempNote = Note(name: "", project: project, type: .Markdown)
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
                self.titleBarView.isHidden = false
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

        guard !previewOnly || previewOnly && UserDefaultsManagement.preview else {
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
