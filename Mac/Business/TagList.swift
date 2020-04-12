//
//  Tag.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 6/23/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

class TagList {
    private let list: [String]?
    
    init(tags: String) {
        var newTagsClean = [String]()
        let newTags = tags.split(separator: ",")
        for newTag in newTags {
            newTagsClean.append(
                String(newTag).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        
        self.list = newTagsClean
    }
    
    public func get() -> [String]? {
        return self.list
    }
}
