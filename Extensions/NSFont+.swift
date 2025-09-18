import Cocoa

extension NSFont {
    var isBold: Bool { fontDescriptor.symbolicTraits.contains(.bold) }

    var isItalic: Bool { fontDescriptor.symbolicTraits.contains(.italic) }

    var height: CGFloat {
        let constraintRect = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        let boundingBox = "A".boundingRect(
            with: constraintRect,
            options: NSString.DrawingOptions.usesLineFragmentOrigin,
            attributes: [.font: self],
            context: nil
        )
        return boundingBox.height
    }

    var lineHeight: CGFloat {
        CGFloat(ceilf(Float(ascender + abs(descender) + leading)))
    }

    // MARK: - 这些方法会读取 UserDefaultsManagement → 标注 @MainActor

    @MainActor
    static func italicFont() -> NSFont {
        NSFontManager().convert(UserDefaultsManagement.noteFont, toHaveTrait: .italicFontMask)
    }

    @MainActor
    static func boldFont() -> NSFont {
        NSFontManager().convert(UserDefaultsManagement.noteFont, toHaveTrait: .boldFontMask)
    }

    @MainActor
    func bold() -> NSFont {
        guard let family = UserDefaultsManagement.noteFont.familyName else {
            return UserDefaultsManagement.noteFont
        }

        let mask: Int = isItalic ? (NSFontBoldTrait | NSFontItalicTrait) : NSFontBoldTrait

        if let font = NSFontManager().font(
            withFamily: family,
            traits: NSFontTraitMask(rawValue: NSFontTraitMask.RawValue(mask)),
            weight: 5,
            size: CGFloat(UserDefaultsManagement.fontSize)
        ) {
            return font
        }

        return UserDefaultsManagement.noteFont
    }

    @MainActor
    func titleBold() -> NSFont {
        guard let family = UserDefaultsManagement.titleFont.familyName else {
            return UserDefaultsManagement.titleFont
        }

        let mask: Int = isItalic ? (NSFontBoldTrait | NSFontItalicTrait) : NSFontBoldTrait

        if let font = NSFontManager().font(
            withFamily: family,
            traits: NSFontTraitMask(rawValue: NSFontTraitMask.RawValue(mask)),
            weight: 5,
            size: CGFloat(UserDefaultsManagement.titleFontSize)
        ) {
            return font
        }

        return UserDefaultsManagement.titleFont
    }

    @MainActor
    func unBold() -> NSFont {
        guard let family = UserDefaultsManagement.noteFont.familyName else {
            return UserDefaultsManagement.noteFont
        }

        let mask: Int = isItalic ? NSFontItalicTrait : 0

        if let font = NSFontManager().font(
            withFamily: family,
            traits: NSFontTraitMask(rawValue: NSFontTraitMask.RawValue(mask)),
            weight: 5,
            size: CGFloat(UserDefaultsManagement.fontSize)
        ) {
            return font
        }

        return UserDefaultsManagement.noteFont
    }

    @MainActor
    func italic() -> NSFont {
        guard let family = UserDefaultsManagement.noteFont.familyName else {
            return UserDefaultsManagement.noteFont
        }

        let mask: Int = isBold ? (NSFontBoldTrait | NSFontItalicTrait) : NSFontItalicTrait

        if let font = NSFontManager().font(
            withFamily: family,
            traits: NSFontTraitMask(rawValue: NSFontTraitMask.RawValue(mask)),
            weight: 5,
            size: CGFloat(UserDefaultsManagement.fontSize)
        ) {
            return font
        }

        return UserDefaultsManagement.noteFont
    }

    @MainActor
    func unItalic() -> NSFont {
        guard let family = UserDefaultsManagement.noteFont.familyName else {
            return UserDefaultsManagement.noteFont
        }

        let mask: Int = isBold ? NSFontBoldTrait : 0

        if let font = NSFontManager().font(
            withFamily: family,
            traits: NSFontTraitMask(rawValue: NSFontTraitMask.RawValue(mask)),
            weight: 5,
            size: CGFloat(UserDefaultsManagement.fontSize)
        ) {
            return font
        }

        return UserDefaultsManagement.noteFont
    }
}
