//
//  PrefsWindowController.swift
//  FSNotes
//
//  Created by Jeff Hanbury on 13/08/17.
//  Copyright © 2017 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa

class PrefsWindowController: NSWindowController, NSWindowDelegate {

    override func windowDidLoad() {
        super.windowDidLoad()
        self.window?.delegate = self
        self.window?.title = "Preferences"
    }
}
