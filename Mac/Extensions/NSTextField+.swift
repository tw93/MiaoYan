//
// Created by Tw93 on 2022/9/22.
// Copyright (c) 2022 MiaoYan App. All rights reserved.
//

import Cocoa

extension NSTextField {
    func addCharacterSpacing() {
        let labelText = stringValue
        let range = NSMakeRange(0, labelText.count - 1)
        let attributedString = NSMutableAttributedString(string: labelText)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail

        attributedString.addAttribute(.kern, value: 0.5, range: range)
        attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)

        attributedStringValue = attributedString
    }
}
