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
            if let clip = subviews.first as? NSClipView {
                guard let currentHeight = findBarView?.frame.height else { return }

                clip.contentInsets.top = newValue ? CGFloat(currentHeight) : 0
                if newValue, let documentView = documentView {
                    documentView.scroll(NSPoint(x: 0, y: CGFloat(-currentHeight)))
                }
            }

            super.isFindBarVisible = newValue
        }
        get {
            super.isFindBarVisible
        }
    }
}
