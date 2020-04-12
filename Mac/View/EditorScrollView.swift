//
//  EditorScrollView.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 10/7/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa

class EditorScrollView: NSScrollView {
    private var initialHeight: CGFloat?

    override var isFindBarVisible: Bool {
        set {
            // macOS 10.14 margin hack
            
            if #available(OSX 10.14, *) {
                if let clip = self.subviews.first as? NSClipView {
                    clip.contentInsets.top = newValue ? 40 : 10

                    if newValue, let documentView = self.documentView {
                        documentView.scroll(NSPoint(x: 0, y: -40))
                    }
                }
            }

            super.isFindBarVisible = newValue
        }
        get {
            return super.isFindBarVisible
        }
    }


    override func findBarViewDidChangeHeight() {
       if #available(OSX 10.14, *) {
            guard let currentHeight = findBarView?.frame.height else { return }

            guard let initialHeight = self.initialHeight else {
                self.initialHeight = currentHeight
                return
            }

            if let clip = self.subviews.first as? NSClipView {
                let margin = currentHeight > initialHeight ? 65 : 40
                clip.contentInsets.top = CGFloat(margin)

                if let documentView = self.documentView {
                    documentView.scroll(NSPoint(x: 0, y: -margin))
                }
            }
        } else {
            super.findBarViewDidChangeHeight()
        }
    }
}
