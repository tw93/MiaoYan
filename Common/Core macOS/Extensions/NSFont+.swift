//
//  NSFont+.swift
//  FSNotesCore macOS
//
//  Created by Oleksandr Glushchenko on 10/14/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

extension NSFont {
    public var lineHeight: CGFloat {
        return CGFloat(ceilf(Float(ascender + abs(descender) + leading)))
    }

    public var lineHeightCustom: CGFloat {
        return CGFloat(ceilf(Float(ascender + abs(descender) + leading)))
    }
}
