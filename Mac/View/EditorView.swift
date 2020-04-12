//
//  EditorView.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 9/29/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa

class EditorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if UserDefaultsManagement.appearanceType != AppearanceType.Custom, #available(OSX 10.13, *) {
            NSColor(named: "mainBackground")!.setFill()
            __NSRectFill(dirtyRect)
        } else {
            layer?.backgroundColor = NSColor.white.cgColor
        }
    }
}
