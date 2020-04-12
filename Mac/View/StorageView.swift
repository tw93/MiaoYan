//
//  StorageView.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 4/6/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Foundation
import Cocoa

class StorageView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        layer?.backgroundColor = NSColor(red:0.96, green:0.96, blue:0.96, alpha:1.0).cgColor
    }
}
