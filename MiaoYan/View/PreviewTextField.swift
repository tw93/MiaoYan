//
//  PreviewTextField.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 10/28/17.
//  Copyright © 2017 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa

class PreviewTextField: NSTextField {
    override var intrinsicContentSize: NSSize {
        if maximumNumberOfLines == -1 {
            let width = super.intrinsicContentSize.width

            return NSSize(width: width, height: 0)
        }

        return super.intrinsicContentSize
    }
}
