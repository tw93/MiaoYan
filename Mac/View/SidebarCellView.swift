//
//  SidebarCellView.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 4/7/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa

class SidebarCellView: NSTableCellView {
    @IBOutlet weak var icon: NSImageView!
    @IBOutlet weak var label: NSTextField!
    @IBOutlet weak var plus: NSButton!
    
    var storage = Storage.sharedInstance()
    
    override func draw(_ dirtyRect: NSRect) {
        plus.isHidden = true

        super.draw(dirtyRect)
    }
    
    private var trackingArea: NSTrackingArea?
    
    override func updateTrackingAreas() {
        if let trackingArea = self.trackingArea {
            self.removeTrackingArea(trackingArea)
        }
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        let trackingArea = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
        self.addTrackingArea(trackingArea)
    }
    
    
    @IBAction func projectName(_ sender: NSTextField) {
        let cell = sender.superview as? SidebarCellView
        guard let si = cell?.objectValue as? SidebarItem, let project = si.project else { return }
        
        let newURL = project.url.deletingLastPathComponent().appendingPathComponent(sender.stringValue)
        
        do {
            try FileManager.default.moveItem(at: project.url, to: newURL)
            project.url = newURL
            project.label = newURL.lastPathComponent
            
        } catch {
            sender.stringValue = project.url.lastPathComponent
            let alert = NSAlert()
            alert.messageText = error.localizedDescription
            alert.runModal()
        }
        
        guard let vc = self.window?.contentViewController as? ViewController else { return }
        vc.storage.removeBy(project: project)
        vc.storage.loadLabel(project)
        vc.updateTable()
    }
    
    @IBAction func add(_ sender: Any) {
        guard let vc = ViewController.shared() else { return }
        vc.storageOutlineView.addProject(self)
    }
    
}
