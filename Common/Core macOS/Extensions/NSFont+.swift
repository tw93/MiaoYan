public extension NSFont {
    var lineHeight: CGFloat {
        CGFloat(ceilf(Float(ascender + abs(descender) + leading)))
    }

    var lineHeightCustom: CGFloat {
        CGFloat(ceilf(Float(ascender + abs(descender) + leading)))
    }
}
