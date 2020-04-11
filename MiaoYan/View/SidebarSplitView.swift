//
//  SidebarSplitView.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 9/29/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa

class SidebarSplitView: NSSplitView {
    override var dividerColor: NSColor {
        if UserDefaultsManagement.appearanceType != AppearanceType.Custom, #available(OSX 10.13, *) {
            return NSColor.init(named: "divider")!
        } else {
            return NSColor(red:0.83, green:0.83, blue:0.83, alpha:1.0)
        }
    }
}

