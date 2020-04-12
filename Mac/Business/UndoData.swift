//
//  UndoData.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 4/27/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

class UndoData: NSObject {
    let string: NSAttributedString
    let range: NSRange
    
    init(string: NSAttributedString, range: NSRange) {
        self.string = string
        self.range = range
    }
}
