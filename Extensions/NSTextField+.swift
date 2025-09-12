//
// Created by Tw93 on 2022/9/22.
// Copyright (c) 2022 MiaoYan App. All rights reserved.
//

import Cocoa

extension NSTextField {
    func addCharacterSpacing(isTitle: Bool = false) {
        if let string = attributedStringValue.mutableCopy() as? NSMutableAttributedString {
            let labelText = stringValue
            let range = NSRange(location: 0, length: labelText.count - 1)
            string.addAttribute(.kern, value: UserDefaultsManagement.windowLetterSpacing, range: range)
            string.fixAttributes(in: range)
            attributedStringValue = string
        }
    }
}
