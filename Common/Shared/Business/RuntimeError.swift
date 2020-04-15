//
//  File.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 3/15/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

struct RuntimeError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    public var localizedDescription: String {
        return message
    }
}
