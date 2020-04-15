//
//  Commit.swift
//  FSNotes
//
//  Created by Олександр Глущенко on 9/8/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

class Commit {
    private var date: String?
    private var hash: String

    init(hash: String) {
        self.hash = hash
    }

    public func setDate(date: String) {
        self.date = date
    }

    public func getDate() -> String? {
        return date
    }

    public func getHash() -> String {
        return hash
    }
}
