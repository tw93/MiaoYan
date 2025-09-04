import AppCenterAnalytics
import Cocoa

// MARK: - Editor Management
extension ViewController {

    // MARK: - Preview Management

    func enablePreview() {
        isFocusedTitle = titleLabel.hasFocus()
        cancelTextSearch()
        editArea.window?.makeFirstResponder(notesTableView)
        UserDefaultsManagement.preview = true

        // WebView 保活：先隐藏，更新内容后再动画显示
        if let webView = editArea.markdownView {
            webView.alphaValue = 0.0
            webView.isHidden = false

            // 先更新内容，再显示动画
            refillEditArea()

            // 短暂延迟确保内容加载完成后再显示
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

        // WebView 保活：隐藏并清空内容
        if let webView = editArea.markdownView {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                webView.animator().alphaValue = 0.0
            }) {
                webView.isHidden = true
                webView.alphaValue = 1.0
                // 清空内容避免下次显示残留
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

        // 获取鼠标位置，自动跳转
        let range = editArea.selectedRange

        // 若 selectedIndex > editArea.string.count()，则使用 string.count() 的值。
        // 若最终计算结果为负，则采 0 值。
        let selectedIndex = max(min(range.location, editArea.string.count) - 1, 0)

        let beforeString = editArea.string[..<selectedIndex]
        let hrCount = beforeString.components(separatedBy: "---").count

        if UserDefaultsManagement.previewLocation == "Editing", hrCount > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // PPT场景下的自动跳转
                vc.editArea.markdownView?.slideTo(index: hrCount - 1)
            }
        }

        // 兼容快捷键透传
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
        if let note = notesTableView.getSelectedNote() {
            // 先保存一下标题，防止首次的时候
            titleLabel.saveTitle()
            // 最牛逼格式化的方式
            let formatter = PrettierFormatter(plugins: [MarkdownPlugin()], parser: MarkdownParser())
            formatter.prepare()
            let content = note.content.string
            let cursor = editArea.selectedRanges[0].rangeValue.location
            let top = editAreaScroll.contentView.bounds.origin.y
            let result = formatter.format(content, withCursorAtLocation: cursor)
            switch result {
            case .success(let formatResult):
                // 防止 Prettier 自动加空行
                var newContent = formatResult.formattedString
                if content.last != "\n" {
                    newContent = formatResult.formattedString.removeLastNewLine()
                }
                editArea.insertText(newContent, replacementRange: NSRange(0..<note.content.length))
                editArea.fill(note: note, highlight: true, saveTyping: true, force: false, needScrollToCursor: false)
                editArea.setSelectedRange(NSRange(location: formatResult.cursorOffset, length: 0))
                editAreaScroll.documentView?.scroll(NSPoint(x: 0, y: top))
                formatContent = newContent
                note.save()
                toast(message: NSLocalizedString("🎉 Automatic typesetting succeeded~", comment: ""))
            case .failure(let error):
                print(error)
            }

            Analytics.trackEvent("MiaoYan Format")
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

    // WebView 预加载，避免首次切换时的延迟
    func preloadWebView() {
        // 仅在非预览模式时预加载，避免干扰已有预览
        guard editArea.markdownView == nil, !UserDefaultsManagement.preview else { return }

        // 使用最简单的临时 Note
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
            // 恢复到之前保存的 first responder，而不是强制设置为 notesTableView
            if let restoreResponder = titleLabel.restoreResponder {
                view.window?.makeFirstResponder(restoreResponder)
                titleLabel.restoreResponder = nil  // 清除保存的状态
            } else {
                view.window?.makeFirstResponder(notesTableView)
            }
        } else {
            let currentNote = notesTableView.getSelectedNote()
            updateTitle(newTitle: currentNote?.getTitleWithoutLabel() ?? NSLocalizedString("Untitled Note", comment: "Untitled Note"))
        }
    }
}
