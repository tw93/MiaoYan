import Cocoa
import Foundation

extension AppDelegate {
    enum HandledSchemes: String {
        case miaoyan
        case nv
        case nvALT = "nvalt"
        case file
    }
    enum MiaoYanRoutes: String {
        case find
        case new
        case goto
    }
    enum NvALTRoutes: String {
        case find
        case blank = ""
        case make
        case goto
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard var url = urls.first,
            let scheme = url.scheme
        else { return }
        let path = url.absoluteString.escapePlus()
        if let escaped = URL(string: path) {
            url = escaped
        }
        switch scheme {
        case HandledSchemes.file.rawValue:
            if ViewController.shared() != nil {
                openNotes(urls: urls)
            } else {
                self.urls = urls
            }
        case HandledSchemes.miaoyan.rawValue:
            MiaoYanRouter(url)
        case HandledSchemes.nv.rawValue,
            HandledSchemes.nvALT.rawValue:
            NvALTRouter(url)
        default:
            break
        }
    }
    func openNotes(urls: [URL]) {
        guard let vc = ViewController.shared() else { return }
        UserDefaultsManagement.singleModePath = urls[0].path
        UserDefaultsManagement.isSingleMode = true
        vc.restart()
    }
    func importNotes(urls: [URL]) {
        guard let vc = ViewController.shared() else { return }
        var importedNote: Note?
        var sidebarIndex: Int?
        for url in urls {
            if let items = vc.storageOutlineView.sidebarItems, let note = Storage.sharedInstance().getBy(url: url) {
                if let sidebarItem = items.first(where: { ($0 as? SidebarItem)?.project == note.project }) {
                    sidebarIndex = vc.storageOutlineView.row(forItem: sidebarItem)
                    importedNote = note
                }
            } else {
                let project = Storage.sharedInstance().getMainProject()
                let newUrl = vc.copy(project: project, url: url)
                UserDataService.instance.focusOnImport = newUrl
                UserDataService.instance.skipSidebarSelection = true
            }
        }
        if let note = importedNote, let si = sidebarIndex {
            vc.storageOutlineView.selectRowIndexes([si], byExtendingSelection: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                vc.notesTableView.setSelected(note: note)
            }
        }
    }
    // MARK: - MiaoYan routes
    func MiaoYanRouter(_ url: URL) {
        guard let directive = url.host else { return }
        switch directive {
        case MiaoYanRoutes.find.rawValue:
            RouteMiaoYanFind(url)
        case MiaoYanRoutes.new.rawValue:
            RouteMiaoYanNew(url)
        case MiaoYanRoutes.goto.rawValue:
            RouteMiaoYanGoto(url)
        default:
            break
        }
    }
    /// Handles URLs with the path /find/searchstring1%20searchstring2
    func RouteMiaoYanFind(_ url: URL) {
        let lastPath = url.lastPathComponent
        guard ViewController.shared() != nil else {
            searchQuery = lastPath
            return
        }
        search(query: lastPath)
    }
    func RouteMiaoYanGoto(_ url: URL) {
        let query = url.lastPathComponent.removingPercentEncoding!
        guard let vc = ViewController.shared() else { return }
        let notes = vc.storage.noteList.filter { $0.title == query }
        if notes.count > 1 {
            vc.updateTable {
                DispatchQueue.main.async {
                    vc.storageOutlineView.selectRowIndexes([0], byExtendingSelection: false)
                    self.RouteMiaoYanFind(url)
                    vc.toastMoreTitle()
                }
            }
        } else if notes.count == 1 {
            if let items = vc.storageOutlineView.sidebarItems {
                // 修复在根目录的场景
                var sidebarIndex = 0
                if let sidebarItem = items.first(where: { ($0 as? SidebarItem)?.project == notes[0].project }) {
                    sidebarIndex = vc.storageOutlineView.row(forItem: sidebarItem)
                }
                vc.updateTable {
                    DispatchQueue.main.async {
                        vc.storageOutlineView.selectRowIndexes([sidebarIndex], byExtendingSelection: false)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                            if let index = vc.notesTableView.noteList.firstIndex(where: { $0 === notes[0] }) {
                                vc.notesTableView.selectRowIndexes([index], byExtendingSelection: false)
                                vc.notesTableView.scrollRowToVisible(row: index, animated: false)
                            }
                        }
                    }
                }
            }
        } else {
            vc.toastNoTitle()
        }
    }
    func search(query: String) {
        guard let controller = ViewController.shared() else { return }
        controller.search.stringValue = query
        controller.updateTable(search: true, searchText: query) {
            if let note = controller.notesTableView.noteList.first {
                DispatchQueue.main.async {
                    controller.search.suggestAutocomplete(note, filter: query)
                }
            }
        }
    }
    /// Handles URLs with the following paths:
    ///   - miaoyan://make/?title=URI-escaped-title&html=URI-escaped-HTML-data
    ///   - miaoyan://make/?title=URI-escaped-title&txt=URI-escaped-plain-text
    ///   - miaoyan://make/?txt=URI-escaped-plain-text
    ///
    /// The three possible parameters (title, txt, html) are all optional.
    ///
    func RouteMiaoYanNew(_ url: URL) {
        var title = ""
        var body = ""
        if let titleParam = url["title"] {
            title = titleParam
        }
        if let txtParam = url["txt"] {
            body = txtParam
        } else if let htmlParam = url["html"] {
            body = htmlParam
        }
        guard ViewController.shared() != nil else {
            newName = title
            newContent = body
            return
        }
        create(name: title, content: body)
    }
    func create(name: String, content: String) {
        guard let controller = ViewController.shared() else { return }
        controller.createNote(name: name, content: content)
    }
    // MARK: - nvALT routes, for compatibility
    func NvALTRouter(_ url: URL) {
        guard let directive = url.host else { return }
        switch directive {
        case NvALTRoutes.find.rawValue:
            RouteNvAltFind(url)
        case NvALTRoutes.make.rawValue:
            RouteNvAltMake(url)
        case NvALTRoutes.goto.rawValue:
            RouteNvAltGoto(url)
        default:
            RouteNvAltBlank(url)
        }
    }
    /// Handle URLs in the format nv://find/searchstring1%20searchstring2
    ///
    /// Note: this route is identical to the corresponding MiaoYan route.
    ///
    func RouteNvAltFind(_ url: URL) {
        RouteMiaoYanFind(url)
    }
    func RouteNvAltGoto(_ url: URL) {
        RouteMiaoYanGoto(url)
    }
    /// Handle URLs in the format nv://note%20title
    ///
    /// Note: this route is an alias to the /find route above.
    ///
    func RouteNvAltBlank(_ url: URL) {
        let pathWithFind = url.absoluteString.replacingOccurrences(of: "://", with: "://find/")
        guard let newURL = URL(string: pathWithFind) else { return }
        RouteMiaoYanFind(newURL)
    }
    /// Handle URLs in the format:
    ///
    ///   - nv://make/?title=URI-escaped-title&html=URI-escaped-HTML-data&tags=URI-escaped-tag-string
    ///   - nv://make/?title=URI-escaped-title&txt=URI-escaped-plain-text
    ///   - nv://make/?txt=URI-escaped-plain-text
    ///
    /// The four possible parameters (title, txt, html and tags) are all optional.
    ///
    func RouteNvAltMake(_ url: URL) {
        var title = ""
        var body = ""
        if let titleParam = url["title"] {
            title = titleParam
        }
        if let txtParam = url["txt"] {
            body = txtParam
        } else if let htmlParam = url["html"] {
            body = htmlParam
        }
        if let tagsParam = url["tags"] {
            body = body.appending("\n\nnvALT tags: \(tagsParam)")
        }
        guard let controller = ViewController.shared() else { return }
        controller.createNote(name: title, content: body)
    }
}

