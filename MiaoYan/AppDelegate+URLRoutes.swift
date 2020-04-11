//
//  AppDelegate+URLRoutes.swift
//  FSNotes
//
//  Created by Jeff Hanbury on 13/04/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Foundation
import Cocoa


extension AppDelegate {
    
    enum HandledSchemes: String {
        case fsnotes = "fsnotes"
        case nv = "nv"
        case nvALT = "nvalt"
        case file = "file"
    }
    
    enum FSNotesRoutes: String {
        case find = "find"
        case new = "new"
    }
    
    enum NvALTRoutes: String {
        case find = "find"
        case blank = ""
        case make = "make"
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
            if nil != ViewController.shared() {
                self.importNotes(urls: urls)
            } else {
                self.urls = urls
            }
        case HandledSchemes.fsnotes.rawValue:
            FSNotesRouter(url)
        case HandledSchemes.nv.rawValue,
             HandledSchemes.nvALT.rawValue:
            NvALTRouter(url)
        default:
            break
        }
    }

    func importNotes(urls: [URL]) {
        guard let vc = ViewController.shared() else { return }

        var importedNote: Note? = nil
        var sidebarIndex: Int? = nil

        for url in urls {
            if let items = vc.storageOutlineView.sidebarItems, let note = Storage.sharedInstance().getBy(url: url) {
                if let sidebarItem = items.first(where: { ($0 as? SidebarItem)?.project == note.project || ($0 as? SidebarItem)?.project?.isArchive == note.isInArchive()}) {
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: {
                vc.notesTableView.setSelected(note: note)
            })
        }
    }
    
    // MARK: - FSNotes routes
    
    func FSNotesRouter(_ url: URL) {
        guard let directive = url.host else { return }
        
        switch directive {
        case FSNotesRoutes.find.rawValue:
            RouteFSNotesFind(url)
        case FSNotesRoutes.new.rawValue:
            RouteFSNotesNew(url)
        default:
            break
        }
    }
    
    /// Handles URLs with the path /find/searchstring1%20searchstring2
    func RouteFSNotesFind(_ url: URL) {
        let lastPath = url.lastPathComponent

        guard nil != ViewController.shared() else {
            self.searchQuery = lastPath
            return
        }

        search(query: lastPath)
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
    ///   - fsnotes://make/?title=URI-escaped-title&html=URI-escaped-HTML-data
    ///   - fsnotes://make/?title=URI-escaped-title&txt=URI-escaped-plain-text
    ///   - fsnotes://make/?txt=URI-escaped-plain-text
    ///
    /// The three possible parameters (title, txt, html) are all optional.
    ///
    func RouteFSNotesNew(_ url: URL) {
        var title = ""
        var body = ""
        
        if let titleParam = url["title"] {
            title = titleParam
        }
        
        if let txtParam = url["txt"] {
            body = txtParam
        }
        else if let htmlParam = url["html"] {
            body = htmlParam
        }
        
        guard nil != ViewController.shared() else {
            self.newName = title
            self.newContent = body
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
        default:
            RouteNvAltBlank(url)
            break
        }
    }
    
    /// Handle URLs in the format nv://find/searchstring1%20searchstring2
    ///
    /// Note: this route is identical to the corresponding FSNotes route.
    ///
    func RouteNvAltFind(_ url: URL) {
        RouteFSNotesFind(url)
    }
    
    /// Handle URLs in the format nv://note%20title
    ///
    /// Note: this route is an alias to the /find route above.
    ///
    func RouteNvAltBlank(_ url: URL) {
        let pathWithFind = url.absoluteString.replacingOccurrences(of: "://", with: "://find/")
        guard let newURL = URL(string: pathWithFind) else { return }
        
        RouteFSNotesFind(newURL)
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
        }
        else if let htmlParam = url["html"] {
            body = htmlParam
        }
        
        if let tagsParam = url["tags"] {
            body = body.appending("\n\nnvALT tags: \(tagsParam)")
        }
        
        guard let controller = ViewController.shared() else { return }
        
        controller.createNote(name: title, content: body)
    }
}
