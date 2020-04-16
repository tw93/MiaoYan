extension NSFont {
    public var lineHeight: CGFloat {
        return CGFloat(ceilf(Float(ascender + abs(descender) + leading)))
    }

    public var lineHeightCustom: CGFloat {
        return CGFloat(ceilf(Float(ascender + abs(descender) + leading)))
    }
}
