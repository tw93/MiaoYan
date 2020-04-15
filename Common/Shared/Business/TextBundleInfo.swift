//
//  TextBundleInfo.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 3/4/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

struct TextBundleInfo: Decodable {
    let version: Int
    let type: String
    let flatExtension: String?
}
