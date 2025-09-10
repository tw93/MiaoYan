//
// Created by Tw93 on 2022/9/13.
// Copyright (c) 2022 MiaoYan App. All rights reserved.
//

import AppKit

extension NSColor {
    private static let cssColorNames: [String: String] = [
        "black": "#000000",
        "silver": "#C0C0C0",
        "gray": "#808080",
        "white": "#FFFFFF",
        "maroon": "#800000",
        "red": "#FF0000",
        "purple": "#800080",
        "fuchsia": "#FF00FF",
        "green": "#008000",
        "lime": "#00FF00",
        "olive": "#808000",
        "yellow": "#FFFF00",
        "navy": "#000080",
        "blue": "#0000FF",
        "teal": "#008080",
        "aqua": "#00FFFF",
    ]

    convenience init?(css: String) {
        var colorString = css.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let hexValue = NSColor.cssColorNames[colorString] {
            colorString = hexValue
        }
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat
        if colorString.hasPrefix("#") {
            let start = colorString.index(colorString.startIndex, offsetBy: 1)
            let hexColor = String(colorString[start...])
            if hexColor.count == 6 {
                let scanner = Scanner(string: hexColor)
                var hexNumber: UInt64 = 0
                if scanner.scanHexInt64(&hexNumber) {
                    r = CGFloat((hexNumber & 0xFF0000) >> 16) / 255
                    g = CGFloat((hexNumber & 0x00FF00) >> 8) / 255
                    b = CGFloat(hexNumber & 0x0000FF) / 255
                    a = 1.0
                    self.init(red: r, green: g, blue: b, alpha: a)
                    return
                }
            }
        }
        return nil
    }
}
