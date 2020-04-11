//
//  LanguageType.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 7/7/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

//
//  NoteFileType.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 1/6/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

enum LanguageType: Int {
    case English = 0x00
    case Chinese = 0x06
    

    var description: String {
        get {
            switch(self.rawValue) {
            default: return "中文"
            }
        }
    }
    
    var code: String {
        get {
            switch(self.rawValue) {
            default: return "zh-Hans"
            }
        }
    }
    
    static func withName(rawValue: String) -> LanguageType {
        switch rawValue {
        case "中文": return LanguageType.Chinese
        default: return LanguageType.Chinese
        }
    }
    
}
