import Cocoa

extension NSFont {
    var isBold: Bool { fontDescriptor.symbolicTraits.contains(.bold) }

    var isItalic: Bool { fontDescriptor.symbolicTraits.contains(.italic) }

    var height: CGFloat {
        let constraintRect = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let boundingBox = "A".boundingRect(with: constraintRect, options: NSString.DrawingOptions.usesLineFragmentOrigin, attributes: [NSAttributedString.Key.font: self], context: nil)

        return boundingBox.height
    }

    var lineHeight: CGFloat {
        CGFloat(ceilf(Float(ascender + abs(descender) + leading)))
    }

    var lineHeightCustom: CGFloat {
        CGFloat(ceilf(Float(ascender + abs(descender) + leading)))
    }

    static func italicFont() -> NSFont {
        NSFontManager().convert(UserDefaultsManagement.noteFont, toHaveTrait: .italicFontMask)
    }

    static func boldFont() -> NSFont {
        NSFontManager().convert(UserDefaultsManagement.noteFont, toHaveTrait: .boldFontMask)
    }

    func bold() -> NSFont {
        guard let family = UserDefaultsManagement.noteFont.familyName else {
            return UserDefaultsManagement.noteFont
        }

        var mask = 0
        if isItalic {
            mask = NSFontBoldTrait | NSFontItalicTrait
        } else {
            mask = NSFontBoldTrait
        }

        if let font = NSFontManager().font(withFamily: family, traits: NSFontTraitMask(rawValue: NSFontTraitMask.RawValue(mask)), weight: 5, size: CGFloat(UserDefaultsManagement.fontSize)) {
            return font
        }

        return UserDefaultsManagement.noteFont
    }

    func titleBold() -> NSFont {
        guard let family = UserDefaultsManagement.titleFont.familyName else {
            return UserDefaultsManagement.titleFont
        }

        var mask = 0
        if isItalic {
            mask = NSFontBoldTrait | NSFontItalicTrait
        } else {
            mask = NSFontBoldTrait
        }

        if let font = NSFontManager().font(withFamily: family, traits: NSFontTraitMask(rawValue: NSFontTraitMask.RawValue(mask)), weight: 5, size: CGFloat(UserDefaultsManagement.titleFontSize)) {
            return font
        }

        return UserDefaultsManagement.titleFont
    }

    func unBold() -> NSFont {
        guard let family = UserDefaultsManagement.noteFont.familyName else {
            return UserDefaultsManagement.noteFont
        }

        var mask = 0
        if isItalic {
            mask = NSFontItalicTrait
        }

        if let font = NSFontManager().font(withFamily: family, traits: NSFontTraitMask(rawValue: NSFontTraitMask.RawValue(mask)), weight: 5, size: CGFloat(UserDefaultsManagement.fontSize)) {
            return font
        }

        return UserDefaultsManagement.noteFont
    }

    func italic() -> NSFont {
        guard let family = UserDefaultsManagement.noteFont.familyName else {
            return UserDefaultsManagement.noteFont
        }

        var mask = 0
        if isBold {
            mask = NSFontBoldTrait | NSFontItalicTrait
        } else {
            mask = NSFontItalicTrait
        }

        if let font = NSFontManager().font(withFamily: family, traits: NSFontTraitMask(rawValue: NSFontTraitMask.RawValue(mask)), weight: 5, size: CGFloat(UserDefaultsManagement.fontSize)) {
            return font
        }

        return UserDefaultsManagement.noteFont
    }

    func unItalic() -> NSFont {
        guard let family = UserDefaultsManagement.noteFont.familyName else {
            return UserDefaultsManagement.noteFont
        }

        var mask = 0
        if isBold {
            mask = NSFontBoldTrait
        }

        if let font = NSFontManager().font(withFamily: family, traits: NSFontTraitMask(rawValue: NSFontTraitMask.RawValue(mask)), weight: 5, size: CGFloat(UserDefaultsManagement.fontSize)) {
            return font
        }

        return UserDefaultsManagement.noteFont
    }
}
