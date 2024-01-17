//
//  NSTextAttachment+.swift
//  FSNotes
//
//  Created by Олександр Глущенко on 10/2/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

extension NSTextAttachment {
    func isFile() -> Bool {
        #if os(iOS)
            return false
        #endif

        #if os(OSX)
            return (attachmentCell?.cellSize().height == 40)
        #endif
    }
}
