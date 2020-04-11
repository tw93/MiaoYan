//
//  Date+.swift
//  FSNotes iOS
//
//  Created by Oleksandr Glushchenko on 9/25/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

extension Date {
    func toMillis() -> Int64! {
        return Int64(self.timeIntervalSince1970 * 1000)
    }

    static func getCurrentFormattedDate() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"

        return dateFormatter.string(from: Date())
    }
}
