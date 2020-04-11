//
//  MarkdownAttribute.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 1/25/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

enum NoteAttribute {
    static let highlight = NSAttributedString.Key(rawValue: "co.fluder.search.highlight")
    
    static let all = Set<NSAttributedString.Key>([
        highlight
    ])
}
