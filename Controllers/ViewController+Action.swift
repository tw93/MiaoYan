import Carbon
import Cocoa

// MARK: - User Actions and Operations
extension ViewController {

    // MARK: - IBAction Methods
    @IBAction func activeWindow(_ sender: Any) {
        activeShortcut()
    }

    @IBAction func showInfo(_ sender: Any) {
        popover.appearance = NSAppearance(named: NSAppearance.Name.aqua)!

        let selectedCell = notesTableView.view(atColumn: 0, row: notesTableView.selectedRow, makeIfNecessary: false)

        guard let positioningView = selectedCell else {
            return
        }
        let positioningRect = NSRect.zero

        let preferredEdge = NSRectEdge(rectEdge: .maxXEdge)

        popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: preferredEdge)

        let popoverWindowX = popover.contentViewController?.view.window?.frame.origin.x ?? 0
        let popoverWindowY = popover.contentViewController?.view.window?.frame.origin.y ?? 0

        popover.contentViewController?.view.window?.setFrameOrigin(
            NSPoint(x: popoverWindowX + 18, y: popoverWindowY)
        )

        popover.contentViewController?.view.window?.makeKey()
    }

    @IBAction func searchAndCreate(_ sender: Any) {
        guard let vc = ViewController.shared() else {
            return
        }

        let size = vc.splitView.subviews[0].frame.width

        if size == 0 {
            toggleNoteList(self)
        }

        vc.search.window?.makeFirstResponder(vc.search)
    }

    @IBAction func sortDirectionBy(_ sender: NSMenuItem) {
        let name = sender.identifier!.rawValue
        if name == "Ascending", UserDefaultsManagement.sortDirection {
            UserDefaultsManagement.sortDirection = false
            reSortByDirection()
        }
        if name == "Descending", !UserDefaultsManagement.sortDirection {
            UserDefaultsManagement.sortDirection = true
            reSortByDirection()
        }
    }

    @IBAction func sortBy(_ sender: NSMenuItem) {
        if let id = sender.identifier {
            let key = String(id.rawValue.dropFirst(3))
            guard let sortBy = SortBy(rawValue: key) else { return }

            UserDefaultsManagement.sort = sortBy

            if let submenu = sortByOutlet?.submenu {
                for item in submenu.items {
                    item.state = NSControl.StateValue.off
                }
            }

            sender.state = NSControl.StateValue.on

            reSortByDirection()
        }
    }

    @IBAction func quiteApp(_ sender: Any) {
        if UserDefaultsManagement.isSingleMode {
            UserDefaultsManagement.isSingleMode = false
            UserDefaultsManagement.singleModePath = ""
            UserDefaultsManagement.isFirstLaunch = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApplication.shared.terminate(self)
            }
        } else {
            NSApplication.shared.terminate(self)
        }
    }

    @IBAction func makeNote(_ sender: SearchTextField) {
        guard let vc = ViewController.shared() else { return }
        if let type = vc.getSidebarType(), type == .Trash {
            vc.storageOutlineView.deselectAll(nil)
        }

        let value = sender.stringValue

        if !value.isEmpty {
            search.stringValue = String()
            editArea.clear()
            createNote(name: value, content: "")
        } else {
            createNote(content: "")
        }
    }

    @IBAction func fileMenuNewNote(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        if UserDefaultsManagement.magicPPT {
            return
        }
        if let type = vc.getSidebarType(), type == .Trash {
            vc.storageOutlineView.deselectAll(nil)
        }
        vc.focusTable()
        vc.createNote(name: "", content: "")
    }

    @IBAction func singleOpen(_ sender: NSMenuItem) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.begin { result in
            if result == NSApplication.ModalResponse.OK {
                let urls = panel.urls
                UserDefaultsManagement.singleModePath = urls[0].path
                UserDefaultsManagement.isSingleMode = true
                self.restart()
            }
        }
    }

    @IBAction func moveMenu(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        if vc.notesTableView.selectedRow >= 0 {
            vc.loadMoveMenu()

            let moveTitle = I18n.str("Move")
            let moveMenu = vc.noteMenu.item(withTitle: moveTitle)
            let view = vc.notesTableView.rect(ofRow: vc.notesTableView.selectedRow)
            let x = vc.splitView.subviews[0].frame.width + 5
            let general = moveMenu?.submenu?.item(at: 0)

            moveMenu?.submenu?.popUp(positioning: general, at: NSPoint(x: x, y: view.origin.y + 8), in: vc.notesTableView)
        }
    }

    @IBAction func exportMenu(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        if vc.notesTableView.selectedRow >= 0 {
            let exportTitle = I18n.str("Export")
            let exportMenu = vc.noteMenu.item(withTitle: exportTitle)
            let view = vc.notesTableView.rect(ofRow: vc.notesTableView.selectedRow)
            let x = vc.splitView.subviews[0].frame.width + 5
            let general = exportMenu?.submenu?.item(at: 0)

            exportMenu?.submenu?.popUp(positioning: general, at: NSPoint(x: x, y: view.origin.y + 8), in: vc.notesTableView)
        }
    }

    @IBAction func fileName(_ sender: NSTextField) {
        guard let note = notesTableView.getNoteFromSelectedRow() else {
            return
        }

        let value = sender.stringValue
        let url = note.url

        let newName = sender.stringValue + "." + note.url.pathExtension
        let isSoftRename = note.url.lastPathComponent.lowercased() == newName.lowercased()

        if note.project.fileExist(fileName: value, ext: note.url.pathExtension), !isSoftRename {
            alert = NSAlert()
            guard let alert = alert else {
                return
            }

            alert.messageText = "Hmm, something goes wrong 🙈"
            alert.informativeText = "Note with name \"\(value)\" already exists in selected storage."
            alert.runModal()

            note.parseURL()
            sender.stringValue = note.getTitleWithoutLabel()
            return
        }

        guard !value.isEmpty else {
            sender.stringValue = note.getTitleWithoutLabel()
            return
        }

        sender.isEditable = false

        let newUrl = note.getNewURL(name: value)
        UserDataService.instance.focusOnImport = newUrl

        if note.url.path == newUrl.path {
            updateTitleAndFinishImport(note: note, title: value)
            return
        }

        note.overwrite(url: newUrl)

        do {
            try FileManager.default.moveItem(at: url, to: newUrl)
            updateTitleAndFinishImport(note: note, title: value)
        } catch {
            note.overwrite(url: url)
            note.parseURL()
            let originalTitle = note.getTitleWithoutLabel()
            updateTitleAndFinishImport(note: note, title: originalTitle)
        }
    }

    private func updateTitleAndFinishImport(note: Note, title: String) {
        note.title = title
        titleLabel.setStringValueSafely(title)
        titleLabel.updateNotesTableView()
        UserDataService.instance.focusOnImport = nil
    }

    @IBAction func finderMenu(_ sender: NSMenuItem) {
        if let notes = notesTableView.getSelectedNotes() {
            var urls = [URL]()
            for note in notes {
                urls.append(note.url)
            }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    @IBAction func makeMenu(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        if let type = vc.getSidebarType(), type == .Trash {
            vc.storageOutlineView.deselectAll(nil)
        }

        vc.createNote()
    }

    @IBAction func pinMenu(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        vc.pin(vc.notesTableView.selectedRowIndexes)
    }

    @IBAction func renameMenu(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        vc.titleLabel.restoreResponder = vc.view.window?.firstResponder
        switchTitleToEditMode()
    }

    @IBAction func deleteNote(_ sender: Any) {
        guard let vc = ViewController.shared() else {
            return
        }

        let isPreviewSearchVisible = vc.editArea.markdownView?.isSearchBarVisible ?? false
        if vc.titleLabel.hasFocus() || vc.editArea.hasFocus() || vc.search.hasFocus() || UserDefaultsManagement.magicPPT || UserDefaultsManagement.presentation || vc.editArea.isSearchBarVisible || isPreviewSearchVisible {
            return
        }

        guard let notes = vc.notesTableView.getSelectedNotes() else {
            return
        }

        if let si = vc.getSidebarItem(), si.isTrash() {
            removeForever()
            return
        }

        let selectedRow = vc.notesTableView.selectedRowIndexes.min()

        UserDataService.instance.searchTrigger = true

        vc.notesTableView.removeByNotes(notes: notes)

        vc.storage.removeNotes(notes: notes) { urls in

            if let appd = NSApplication.shared.delegate as? AppDelegate,
                let md = appd.mainWindowController
            {
                let undoManager = md.notesListUndoManager

                if let ntv = vc.notesTableView {
                    undoManager.registerUndo(withTarget: ntv, selector: #selector(ntv.unDelete), object: urls)
                    undoManager.setActionName(I18n.str("Delete"))
                }

                if let i = selectedRow, i > -1 {
                    vc.notesTableView.selectRow(i)
                }

                UserDataService.instance.searchTrigger = false
            }

            // Don't disable preview mode when deleting notes
            // Let the selection change handler update the preview with the next note
            vc.editArea.clear()
        }

        NSApp.mainWindow?.makeFirstResponder(vc.notesTableView)
    }

    @IBAction func cleanUnusedAttachments(_ sender: NSMenuItem) {
        guard let vc = ViewController.shared() else {
            return
        }

        storage.findOrphanAttachments { [weak self, weak vc] orphanAttachments in
            guard let self = self, let vc = vc else { return }

            if orphanAttachments.isEmpty {
                vc.toast(message: I18n.str("No orphan attachments found"))
                return
            }

            let confirmAlert = NSAlert()
            confirmAlert.messageText = I18n.str("Clean Orphan Attachments")
            confirmAlert.informativeText = String(format: I18n.str("Detected %d unused attachment(s). Move them to Trash?"), orphanAttachments.count)
            confirmAlert.addButton(withTitle: I18n.str("Clean"))
            confirmAlert.addButton(withTitle: I18n.str("Cancel"))
            confirmAlert.alertStyle = .warning

            let response = confirmAlert.runModal()
            guard response == .alertFirstButtonReturn else {
                return
            }

            let result = self.storage.removeAttachments(urls: orphanAttachments)

            if !result.removed.isEmpty {
                NSSound(named: "Pop")?.play()
                vc.toast(message: String(format: I18n.str("Removed %d unused attachment(s)"), result.removed.count))
            }

            if !result.failed.isEmpty {
                let failureAlert = NSAlert()
                failureAlert.messageText = I18n.str("Some attachments could not be removed")
                failureAlert.informativeText = I18n.str("Please try again")
                failureAlert.addButton(withTitle: I18n.str("OK"))
                failureAlert.alertStyle = .warning
                failureAlert.runModal()
            }
        }
    }

    @IBAction func openProjectViewSettings(_ sender: NSMenuItem) {
        guard let vc = ViewController.shared() else {
            return
        }

        if let controller = vc.storyboard?.instantiateController(withIdentifier: "ProjectSettingsViewController")
            as? ProjectSettingsViewController
        {
            projectSettingsViewController = controller

            if let project = vc.getSidebarProject() {
                vc.presentAsSheet(controller)
                controller.load(project: project)
            }
        }
    }

    @IBAction func duplicate(_ sender: Any) {
        if let notes = notesTableView.getSelectedNotes() {
            for note in notes {
                guard let name = note.getDupeName() else {
                    continue
                }
                let noteDupe = Note(name: name, project: note.project, type: note.type)
                noteDupe.content = NSMutableAttributedString(string: note.content.string)

                // Clone images
                if note.type == .markdown, note.container == .none {
                    let images = note.getAllImages()
                    for image in images {
                        move(note: noteDupe, from: image.url, imagePath: image.path, to: note.project, copy: true)
                    }
                }

                noteDupe.save()

                storage.add(noteDupe)
                notesTableView.insertNew(note: noteDupe)
            }
        }
    }

    @IBAction func noteCopy(_ sender: Any) {
        guard let responder = view.window?.firstResponder else { return }

        if self.responder(responder, belongsTo: editArea) {
            editArea.copy(sender)
            return
        }

        if let preview = editArea.markdownView,
            self.responder(responder, belongsTo: preview)
        {
            preview.copySelectionToPasteboard()
            return
        }

        if self.responder(responder, belongsTo: notesTableView) {
            saveTextAtClipboard()
        }
    }

    @IBAction func copyURL(_ sender: Any) {
        if let note = notesTableView.getSelectedNote(), let title = note.title.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
            let name = "miaoyan://goto/\(title)"
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(name, forType: NSPasteboard.PasteboardType.string)
            toast(message: I18n.str("🎉 URL is successfully copied, Use it anywhere~"))
        }
    }

    private func responder(_ responder: NSResponder, belongsTo view: NSView?) -> Bool {
        guard let view else { return false }

        if let responderView = responder as? NSView {
            return responderView === view || responderView.isDescendant(of: view)
        }

        return responder === view
    }

    @IBAction func copyTitle(_ sender: Any) {
        if let note = notesTableView.getSelectedNote() {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(note.title, forType: NSPasteboard.PasteboardType.string)
        }
    }

    @IBAction func exportImage(_ sender: Any) {
        exportFile(type: "Image")
    }

    @IBAction func exportHtml(_ sender: Any) {
        exportFile(type: "Html")
    }

    @IBAction func exportPdf(_ sender: Any) {
        exportFile(type: "PDF")
    }

    @IBAction func exportMiaoYanPPT(_ sender: Any) {
        guard isMiaoYanPPT() else { return }

        // Only enable PPT mode if not already enabled
        let needsDisableAfterExport = !UserDefaultsManagement.magicPPT
        if needsDisableAfterExport {
            enableMiaoYanPPT()
        }
        shouldDisablePPTAfterExport = needsDisableAfterExport

        // Mark export state
        UserDefaultsManagement.isOnExportPPT = true

        // Short delay then export (1.2s is sufficient for PPT layout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.editArea.markdownView?.exportPPTOptimized()
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    @IBAction func textFinder(_ sender: NSMenuItem) {
        guard let vc = ViewController.shared() else { return }

        if UserDefaultsManagement.preview || UserDefaultsManagement.presentation || UserDefaultsManagement.magicPPT {
            if let webView = vc.editArea.markdownView {
                if vc.editArea.isSearchBarVisible {
                    vc.editArea.hideSearchBar()
                }
                if sender.tag == NSFindPanelAction.next.rawValue {
                    webView.findNext()
                    return
                }
                if sender.tag == NSFindPanelAction.previous.rawValue {
                    webView.findPrevious()
                    return
                }
                
                if let textFinderAction = NSTextFinder.Action(rawValue: sender.tag) {
                    if textFinderAction == .showReplaceInterface {
                        webView.showSearchBar(mode: .replace)
                        return
                    }
                }
                
                webView.showSearchBar(mode: .find)
                return
            }
            return
        }

        if let action = NSFindPanelAction(rawValue: UInt(sender.tag)) {
            switch action {
            case .next:
                if !vc.editArea.isSearchBarVisible {
                    vc.editArea.showSearchBar(prefilledText: vc.editArea.currentSearchQuery)
                }
                vc.editArea.findNext()
                return
            case .previous:
                if !vc.editArea.isSearchBarVisible {
                    vc.editArea.showSearchBar(prefilledText: vc.editArea.currentSearchQuery)
                }
                vc.editArea.findPrevious()
                return
            case .setFindString:
                vc.editArea.useSelectionForFind()
                return
            default:
                break
            }
        }

        if let textFinderAction = NSTextFinder.Action(rawValue: sender.tag) {
            switch textFinderAction {
            case .showFindInterface:
                vc.editArea.showSearchBar(prefilledText: nil, mode: .find)
                return
            case .showReplaceInterface:
                vc.editArea.showSearchBar(prefilledText: nil, mode: .replace)
                return
            case .hideFindInterface:
                vc.editArea.hideSearchBar()
                return
            default:
                break
            }
        }

        DispatchQueue.main.async {
            vc.editArea.performTextFinderAction(sender)
        }
    }

    // MARK: - Note Operations
    @objc func moveNote(_ sender: NSMenuItem) {
        let project = sender.representedObject as! Project

        guard let notes = notesTableView.getSelectedNotes() else {
            return
        }

        move(notes: notes, project: project)
    }

    public func move(notes: [Note], project: Project) {
        let selectedRow = notesTableView.selectedRowIndexes.min()
        for note in notes {
            if note.project == project {
                continue
            }

            let destination = project.url.appendingPathComponent(note.name)

            if note.type == .markdown, note.container == .none {
                let imagesMeta = note.getAllImages()
                for imageMeta in imagesMeta {
                    move(note: note, from: imageMeta.url, imagePath: imageMeta.path, to: project)
                }

                if !imagesMeta.isEmpty {
                    note.save()
                }
            }

            _ = note.move(to: destination, project: project)

            if !isFit(note: note, shouldLoadMain: true) {
                notesTableView.removeByNotes(notes: [note])

                if let i = selectedRow, i > -1 {
                    if notesTableView.noteList.count > i {
                        notesTableView.selectRow(i)
                    } else {
                        notesTableView.selectRow(notesTableView.noteList.count - 1)
                    }
                }
            }

            note.invalidateCache()
        }

        editArea.clear()
    }

    private func move(note: Note, from imageURL: URL, imagePath: String, to project: Project, copy: Bool = false) {
        let dstPrefix = NotesTextProcessor.getAttachPrefix(url: imageURL)
        let dest = project.url.appendingPathComponent(dstPrefix)

        if !FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false, attributes: nil)
        }

        do {
            if copy {
                try FileManager.default.copyItem(at: imageURL, to: dest)
            } else {
                try FileManager.default.moveItem(at: imageURL, to: dest)
            }
        } catch {
            if let fileName = ImagesProcessor.getFileName(from: imageURL, to: dest, ext: imageURL.pathExtension) {
                let dest = dest.appendingPathComponent(fileName)

                if copy {
                    try? FileManager.default.copyItem(at: imageURL, to: dest)
                } else {
                    try? FileManager.default.moveItem(at: imageURL, to: dest)
                }

                let prefix = "]("
                let postfix = ")"

                let find = prefix + imagePath + postfix
                let replace = prefix + dstPrefix + fileName + postfix

                guard find != replace else {
                    return
                }

                while note.content.mutableString.contains(find) {
                    let range = note.content.mutableString.range(of: find)
                    note.content.replaceCharacters(in: range, with: replace)
                }
            }
        }
    }

    func createNote(name: String = "", content: String = "", type: NoteType? = nil, project: Project? = nil, load: Bool = false) {
        guard let vc = ViewController.shared() else { return }
        let selectedProjects = vc.storageOutlineView.getSidebarProjects()
        var sidebarProject = project ?? selectedProjects?.first
        let text = content

        if sidebarProject == nil {
            let projects = storage.getProjects()
            sidebarProject = projects.first
        }

        guard let project = sidebarProject else {
            return
        }

        let note = Note(name: name, project: project, type: type)
        note.content = NSMutableAttributedString(string: text)
        note.save()

        if let selectedProjects = selectedProjects, !selectedProjects.contains(project) {
            return
        }

        // Don't force disable preview mode - let user maintain their preferred mode
        // Only clean up the webview if we're NOT in preview mode
        if !UserDefaultsManagement.preview {
            editArea.markdownView?.removeFromSuperview()
            previewScrollView?.documentView = nil
            editArea.markdownView = nil

            guard let editor = editArea else {
                return
            }
            editor.subviews.removeAll(where: { $0.isKind(of: MPreviewView.self) })
        }

        // Set flag to prevent edit area updates during note creation
        UserDataService.instance.isCreatingNote = true

        // Prepare for new note creation - ensure clean state
        prepareForNoteCreation()

        // Set new note content
        editArea.string = text
        EditTextView.note = note

        // Update table and handle completion
        updateTable {
            DispatchQueue.main.async {
                // Clear the flag before final setup
                UserDataService.instance.isCreatingNote = false
                self.completeNoteCreation(for: note, with: vc)
            }
        }
    }

    // Prepare UI state for new note creation
    private func prepareForNoteCreation() {
        notesTableView.deselectNotes()
        search.stringValue.removeAll()
        titleLabel.isEditable = true
    }

    // Complete final setup for newly created note
    private func completeNoteCreation(for note: Note, with viewController: ViewController) {
        guard let index = notesTableView.getIndex(note) else {
            return
        }

        notesTableView.selectRowIndexes([index], byExtendingSelection: false)
        notesTableView.scrollRowToVisible(index)

        // Focus on title after UI stabilizes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            viewController.titleLabel.editModeOn()
        }
    }

    private func removeForever() {
        guard let vc = ViewController.shared() else { return }
        guard let notes = vc.notesTableView.getSelectedNotes() else { return }
        guard let window = MainWindowController.shared() else { return }

        vc.alert = NSAlert()
        guard let alert = vc.alert else { return }

        alert.messageText = String(format: I18n.str("Are you sure you want to irretrievably delete %d note(s)?"), notes.count)

        alert.informativeText = I18n.str("This action cannot be undone.")
        alert.addButton(withTitle: I18n.str("Remove note(s)"))
        alert.addButton(withTitle: I18n.str("Cancel"))
        alert.beginSheetModal(for: window) { (returnCode: NSApplication.ModalResponse) in
            if returnCode == NSApplication.ModalResponse.alertFirstButtonReturn {
                let selectedRow = vc.notesTableView.selectedRowIndexes.min()
                vc.editArea.clear()
                vc.storage.removeNotes(notes: notes) { _ in
                    DispatchQueue.main.async {
                        vc.storageOutlineView.reloadSidebar()
                        vc.notesTableView.removeByNotes(notes: notes)
                        if let i = selectedRow, i > -1 {
                            vc.notesTableView.selectRow(i)
                        }
                        if vc.getSidebarItem() == nil {
                            vc.storageOutlineView.selectRowIndexes([0], byExtendingSelection: false)
                            vc.notesTableView.selectRow(0)
                        }
                    }
                }
            } else {
                self.alert = nil
            }
        }
    }

    func pin(_ selectedRows: IndexSet) {
        guard !selectedRows.isEmpty, let notes = filteredNoteList, var state = filteredNoteList else {
            return
        }

        var updatedNotes = [(Int, Note)]()
        for row in selectedRows {
            guard let rowView = notesTableView.rowView(atRow: row, makeIfNecessary: false) as? NoteRowView,
                let cell = rowView.view(atColumn: 0) as? NoteCellView,
                let note = cell.objectValue as? Note
            else {
                continue
            }

            updatedNotes.append((row, note))
            note.togglePin()
            cell.renderPin()
        }

        let resorted = storage.sortNotes(noteList: notes, filter: search.stringValue)
        let indexes = updatedNotes.compactMap { _, note in
            resorted.firstIndex(where: { $0 === note })
        }
        let newIndexes = IndexSet(indexes)

        notesTableView.beginUpdates()
        let nowPinned = updatedNotes.filter { _, note in
            note.isPinned
        }
        for (row, note) in nowPinned {
            guard let newRow = resorted.firstIndex(where: { $0 === note }) else {
                continue
            }
            notesTableView.moveRow(at: row, to: newRow)
            let toMove = state.remove(at: row)
            state.insert(toMove, at: newRow)
        }

        let nowUnpinned =
            updatedNotes
            .filter { _, note -> Bool in
                !note.isPinned
            }
            .compactMap { _, note -> (Int, Note)? in
                guard let curRow = state.firstIndex(where: { $0 === note }) else {
                    return nil
                }
                return (curRow, note)
            }
        for (row, note) in nowUnpinned.reversed() {
            guard let newRow = resorted.firstIndex(where: { $0 === note }) else {
                continue
            }
            notesTableView.moveRow(at: row, to: newRow)
            let toMove = state.remove(at: row)
            state.insert(toMove, at: newRow)
        }

        notesTableView.noteList = resorted
        notesTableView.reloadData(forRowIndexes: newIndexes, columnIndexes: [0])
        notesTableView.selectRowIndexes(newIndexes, byExtendingSelection: false)
        notesTableView.endUpdates()
        filteredNoteList = resorted
    }

    @objc func switchTitleToEditMode() {
        guard let vc = ViewController.shared() else {
            return
        }

        vc.titleLabel.editModeOn()
    }

    @objc func breakUndo() {
        editArea.breakUndoCoalescing()
    }

    // MARK: - File Operations
    public func copy(project: Project, url: URL) -> URL {
        let fileName = url.lastPathComponent

        do {
            let destination = project.url.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            // If file already exists, create a copy with "Copy" suffix
            let baseName = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension

            var copyName = baseName + " Copy"
            var copyNumber = 2

            while FileManager.default.fileExists(atPath: project.url.appendingPathComponent(copyName).appendingPathExtension(ext).path) {
                copyName = baseName + " Copy \(copyNumber)"
                copyNumber += 1
            }

            let baseUrl = project.url.appendingPathComponent(copyName).appendingPathExtension(ext)
            try? FileManager.default.copyItem(at: url, to: baseUrl)

            return baseUrl
        }
    }

    func restart() {
        AppDelegate.relaunchApp()
    }

    // MARK: - Menu Management
    func loadMoveMenu() {
        guard let vc = ViewController.shared(), let note = vc.notesTableView.getSelectedNote() else { return }

        let moveTitle = I18n.str("Move")
        if let prevMenu = noteMenu.item(withTitle: moveTitle) {
            noteMenu.removeItem(prevMenu)
        }

        let moveMenuItem = NSMenuItem()
        moveMenuItem.title = I18n.str("Move")
        moveMenuItem.setIdentifier("noteMenu.move")

        if #available(macOS 11.0, *),
            let symbolName = MenuIconRegistry.symbol(for: moveMenuItem),
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: moveMenuItem.title)
        {
            image.isTemplate = true
            moveMenuItem.image = image
        }

        noteMenu.addItem(moveMenuItem)
        let moveMenu = NSMenu()

        if !note.isTrash() {
            let trashMenu = NSMenuItem()
            trashMenu.title = I18n.str("Trash")
            trashMenu.action = #selector(vc.deleteNote(_:))
            trashMenu.tag = 555
            if #available(macOS 11.0, *) {
                trashMenu.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Trash")
            }
            moveMenu.addItem(trashMenu)
            moveMenu.addItem(NSMenuItem.separator())
        }

        let projects = storage.getProjects()
        for item in projects {
            if note.project == item || item.isTrash {
                continue
            }

            let menuItem = NSMenuItem()
            menuItem.title = item.label
            menuItem.representedObject = item
            menuItem.action = #selector(vc.moveNote(_:))
            if #available(macOS 11.0, *) {
                menuItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Folder")
            }
            moveMenu.addItem(menuItem)
        }

        let personalSelection = [
            "noteMove.rename"
        ]

        for menu in noteMenu.items {
            if let identifier = menu.identifier?.rawValue,
                personalSelection.contains(identifier)
            {
                menu.isHidden = (vc.notesTableView.selectedRowIndexes.count > 1)
            }
        }

        if #available(macOS 11.0, *) {
            moveMenu.applyMenuIcons()
            noteMenu.applyMenuIcons()
        }

        noteMenu.setSubmenu(moveMenu, for: moveMenuItem)
    }

    func loadSortBySetting() {
        let viewLabel = I18n.str("View")
        let sortByLabel = I18n.str("Sort by")

        guard
            let menu = NSApp.menu,
            let view = menu.item(withTitle: viewLabel),
            let submenu = view.submenu,
            let sortMenu = submenu.item(withTitle: sortByLabel),
            let sortItems = sortMenu.submenu
        else {
            return
        }

        let sort = UserDefaultsManagement.sort

        for item in sortItems.items {
            if let id = item.identifier, id.rawValue == "SB.\(sort.rawValue)" {
                item.state = NSControl.StateValue.on
            }
        }
    }

    // MARK: - Clipboard Operations
    public func saveTextAtClipboard() {
        if let note = notesTableView.getSelectedNote() {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(note.content.string, forType: NSPasteboard.PasteboardType.string)
        }
    }

    public func saveHtmlAtClipboard() {
        if let note = notesTableView.getSelectedNote() {
            let useGithubLineBreak = UserDefaultsManagement.editorLineBreak == "Github"
            if let render = renderMarkdownHTML(markdown: note.content.string, useGithubLineBreak: useGithubLineBreak) {
                let pasteboard = NSPasteboard.general
                pasteboard.declareTypes([NSPasteboard.PasteboardType.html], owner: nil)
                pasteboard.setString(render, forType: NSPasteboard.PasteboardType.html)
            }
        }
    }

    // MARK: - Export Operations
    func exportFile(type: String) {
        UserDefaultsManagement.isOnExport = true
        shouldRestorePreviewAfterExport = false

        if type == "Html" {
            UserDefaultsManagement.isOnExportHtml = true
            // HTML export can be done immediately without preview
            self.editArea.markdownView?.exportHtml()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                UserDefaultsManagement.isOnExport = false
                UserDefaultsManagement.isOnExportHtml = false
            }
            return
        }

        // For PDF and Image exports, enable preview and wait for proper loading
        // For PDF and Image exports, ensure preview is enabled
        // Only toggle if not already in preview to avoid unnecessary reload
        if !UserDefaultsManagement.preview {
            enablePreview()
            shouldRestorePreviewAfterExport = true
        }

        // Wait briefly for view initialization if needed, then trigger export
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            switch type {
            case "Image":
                self.editArea.markdownView?.exportImage()
            case "PDF":
                self.editArea.markdownView?.exportPdf()
            default:
                break
            }
            // Logic for cleanup is handled in the completion callbacks (toastExport)
        }
    }

    public func toastExport(status: Bool) {
        if status {
            toast(message: I18n.str("🎉 Saved to Downloads folder~"))
        } else {
            toast(message: "😶‍🌫 \(I18n.str("Export failed"))")
        }
        // After the export is completed, restore the original state.
        UserDefaultsManagement.isOnExport = false
        UserDefaultsManagement.isOnExportPPT = false
        UserDefaultsManagement.isOnExportHtml = false
        shouldDisablePPTAfterExport = false
        if shouldRestorePreviewAfterExport {
            disablePreview()
            shouldRestorePreviewAfterExport = false
        }
    }

    public func toastNoTitle() {
        toast(message: I18n.str("😶‍🌫 Please make sure your title exists~"))
    }

    public func toastMoreTitle() {
        toast(message: I18n.str("🍭 Found that there are multiple titles of this~"))
    }

    public func toastImageSet(name: String) {
        toast(message: String(format: I18n.str("🙊 Please make sure your Mac is installed %@ ~"), name))
    }

    public func toastUpload(status: Bool) {
        if status {
            toast(message: I18n.str("🍭 Image upload in progress~"))
        } else {
            toast(message: I18n.str("😶‍🌫 Image upload failed, Use local~"))
        }
    }

    // MARK: - Utility Methods
    func activeShortcut() {
        guard let mainWindow = MainWindowController.shared() else {
            return
        }

        if NSApplication.shared.isActive,
            !NSApplication.shared.isHidden,
            !mainWindow.isMiniaturized
        {
            NSApplication.shared.hide(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(self)
    }

    public func replace(validateString: String, regex: String, content: String) -> String {
        do {
            let RE = try NSRegularExpression(pattern: regex, options: .caseInsensitive)
            let modified = RE.stringByReplacingMatches(in: validateString, options: .reportProgress, range: NSRange(location: 0, length: validateString.count), withTemplate: content)
            return modified
        } catch {
            return validateString
        }
    }

    // MARK: - Keyboard Event Handling
    // swiftlint:disable:next cyclomatic_complexity
    public func keyDown(with event: NSEvent) -> Bool {

        guard let mw = MainWindowController.shared() else {
            return false
        }

        guard alert == nil else {
            if event.keyCode == kVK_Escape, let unwrapped = alert {
                mw.endSheet(unwrapped.window)
                alert = nil
            }

            return true
        }

        if event.modifierFlags.contains(.shift), event.modifierFlags.contains(.control), event.keyCode == kVK_ANSI_H {
            exportHtml(self)
            return false
        }

        if event.keyCode == kVK_Escape {
            if UserDefaultsManagement.magicPPT {
                disableMiaoYanPPT()
                return false
            } else if UserDefaultsManagement.presentation {
                disablePresentation()
                return false
            }
        }

        if event.keyCode == kVK_Delete, event.modifierFlags.contains(.command), search.hasFocus() {
            search.stringValue.removeAll()
            configureNotesList()
            return false
        }

        if event.keyCode == kVK_Escape, search.hasFocus() {
            search.stringValue.removeAll()
            configureNotesList()
            return false
        }

        if event.keyCode == kVK_Escape, titleLabel.hasFocus() {
            focusEditArea()
            return false
        }

        if event.keyCode == kVK_Delete, event.modifierFlags.contains(.command), editArea.hasFocus(), !UserDefaultsManagement.presentation {
            editArea.deleteToBeginningOfLine(nil)
            return false
        }

        if event.keyCode == kVK_Delete, event.modifierFlags.contains(.command), titleLabel.hasFocus(), !UserDefaultsManagement.preview {
            updateTitle(newTitle: "")
            return false
        }

        if event.keyCode == kVK_ANSI_D, event.modifierFlags.contains(.command), editArea.hasFocus() {
            return false
        }

        if event.keyCode == kVK_ANSI_Z, event.modifierFlags.contains(.command), titleLabel.hasFocus() {
            let currentNote = notesTableView.getSelectedNote()
            updateTitle(newTitle: currentNote?.getTitleWithoutLabel() ?? I18n.str("Untitled Note"))
            return false
        }

        if event.keyCode == kVK_ANSI_Z, event.modifierFlags.contains(.command), editArea.hasFocus(), formatContent != "" {
            if let note = notesTableView.getSelectedNote(), note.content.string == formatContent {
                let cursor = editArea.selectedRanges[0].rangeValue.location
                DispatchQueue.main.async {
                    self.editArea.setSelectedRange(NSRange(location: cursor, length: 0))
                }
                formatContent = ""
            }
        }

        if event.modifierFlags.contains(.command), event.keyCode == kVK_ANSI_1, !UserDefaultsManagement.presentation {
            toggleSidebarPanel(self)
            return false
        }

        if event.modifierFlags.contains(.command), event.modifierFlags.contains(.option), event.keyCode == kVK_ANSI_I, !UserDefaultsManagement.presentation {
            toggleInfo()
            return false
        }

        if event.modifierFlags.contains(.command), event.modifierFlags.contains(.option), event.keyCode == kVK_ANSI_U {
            copyURL(self)
            return false
        }

        if event.keyCode == kVK_ANSI_W, event.modifierFlags.contains(.command), event.modifierFlags.contains(.shift) {
            if UserDefaultsManagement.isSingleMode {
                UserDefaultsManagement.isSingleMode = false
                UserDefaultsManagement.isFirstLaunch = true
                UserDefaultsManagement.singleModePath = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.restart()
                }
            }
            return false
        }

        // Up/Down arrow navigation in notes list
        if event.keyCode == kVK_UpArrow || event.keyCode == kVK_DownArrow {
            if let fr = NSApp.mainWindow?.firstResponder, fr.isKind(of: NotesTableView.self), !event.modifierFlags.contains(.command) {
                if event.keyCode == kVK_UpArrow {
                    notesTableView.selectPrev()
                } else {
                    notesTableView.selectNext()
                }
                return false
            }
        }

        // Return / Cmd + Return navigation
        if event.keyCode == kVK_Return {
            if let fr = NSApp.mainWindow?.firstResponder, alert == nil {
                // Ensure selection handling works correctly in PPT mode
                if UserDefaultsManagement.magicPPT {
                    DispatchQueue.main.async {
                        self.editArea.markdownView!.evaluateJavaScript("Reveal.toggleOverview();", completionHandler: nil)
                    }
                    return false
                }

                if event.modifierFlags.contains(.command) {
                    if fr.isKind(of: NotesTableView.self) {
                        NSApp.mainWindow?.makeFirstResponder(storageOutlineView)
                        return false
                    }
                } else {
                    if fr.isKind(of: SidebarProjectView.self) {
                        notesTableView.selectNext()
                        NSApp.mainWindow?.makeFirstResponder(notesTableView)
                        return false
                    }

                    if fr.isKind(of: NotesTableView.self), !(UserDefaultsManagement.preview) {
                        NSApp.mainWindow?.makeFirstResponder(editArea)
                        return false
                    }

                    // Handle the different input behavior used in Japanese locales
                    if titleLabel.hasFocus() {
                        if UserDefaultsManagement.defaultLanguage != 0x02 {
                            focusEditArea()
                        }
                        return false
                    }
                }
            }

            return true
        }

        // Tab / Control + Tab
        if event.keyCode == kVK_Tab {
            if event.modifierFlags.contains(.control) {
                notesTableView.window?.makeFirstResponder(notesTableView)
                return true
            }

            if let fr = NSApp.mainWindow?.firstResponder, fr.isKind(of: NotesTableView.self) {
                NSApp.mainWindow?.makeFirstResponder(notesTableView)
                return false
            }

            // Handle TAB in title field - save and switch to editor
            if let fr = NSApp.mainWindow?.firstResponder, fr.isKind(of: NSTextView.self),
                titleLabel.hasFocus()
            {
                saveTitleSafely()
                focusEditArea()
                return true
            }
        }

        // Focus search bar on ESC
        if event.characters == ".",
            event.modifierFlags.contains(.command),

            NSApplication.shared.mainWindow == NSApplication.shared.keyWindow
        {
            UserDataService.instance.resetLastSidebar()

            if let view = NSApplication.shared.mainWindow?.firstResponder as? NSTextView, let textField = view.superview?.superview, textField.isKind(of: NameTextField.self) {
                NSApp.mainWindow?.makeFirstResponder(notesTableView)
                return false
            }

            if editArea.isSearchBarVisible || (editArea.markdownView?.isSearchBarVisible ?? false) {
                cancelTextSearch()
                return false
            }

            // Renaming is in progress
            if titleLabel.isEditable {
                titleLabel.window?.makeFirstResponder(notesTableView)
                return false
            }

            UserDefaultsManagement.lastProject = 0
            UserDefaultsManagement.lastSelectedURL = nil

            notesTableView.scroll(.zero)

            let hasSelectedNotes = notesTableView.selectedRow > -1
            let hasSelectedBarItem = storageOutlineView.selectedRow > -1

            if hasSelectedBarItem, hasSelectedNotes {
                UserDefaultsManagement.lastProject = 0
                UserDataService.instance.isNotesTableEscape = true
                notesTableView.deselectAll(nil)
                NSApp.mainWindow?.makeFirstResponder(search)
                return false
            }

            storageOutlineView.deselectAll(nil)
            cleanSearchAndEditArea()

            return true
        }

        if event.keyCode == kVK_ANSI_F, event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.control) {
            if notesTableView.getSelectedNote() != nil {
                // If in preview mode, use WebView search instead of exiting preview
                if UserDefaultsManagement.preview || UserDefaultsManagement.presentation || UserDefaultsManagement.magicPPT {
                    if let webView = editArea.markdownView {
                        webView.showSearchBar()
                        return true
                    }
                }
                // Otherwise use editor search
                editArea.showSearchBar(prefilledText: nil)
                return true
            }
        }

        if event.keyCode == kVK_ANSI_Slash, event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.control) {
            if notesTableView.getSelectedNote() != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if self.titleLabel.isEditable {
                        self.fileName(self.titleLabel)
                    }
                }
                NSApp.mainWindow?.makeFirstResponder(search)
                return true
            }
        }

        if event.modifierFlags.contains(.command), event.keyCode == kVK_ANSI_1, !UserDefaultsManagement.presentation {
            toggleSidebarPanel("")
            return false
        }

        if event.modifierFlags.contains(.command), event.keyCode == kVK_ANSI_S {
            if titleLabel.isEditable {
                fileName(titleLabel)
            }
            return false
        }

        if let fr = mw.firstResponder, !fr.isKind(of: EditTextView.self), !fr.isKind(of: NSTextView.self), !event.modifierFlags.contains(.command),
            !event.modifierFlags.contains(.control)
        {
            if let char = event.characters {
                let newSet = CharacterSet(charactersIn: char)
                if newSet.isSubset(of: CharacterSet.alphanumerics) {
                    _ = search.becomeFirstResponder()
                }
            }
        }

        return true
    }

    // MARK: - Info Panel Management
    func toggleInfo() {
        if popoverVisible {
            popover.performClose(nil)
        } else {
            showInfo("")
        }
    }

    private var popoverVisible: Bool {
        popover.isShown
    }

    func toastInSingleMode() {
        toast(message: I18n.str("🙊 In single open mode, Exit with Command+Shift+W ~"))
    }
}
