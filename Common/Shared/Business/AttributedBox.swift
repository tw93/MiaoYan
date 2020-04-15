//
//  AttributedBox.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 8/30/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

#if os(iOS)
    import UIKit
    import NightNight
#else
    import Cocoa
#endif

class AttributedBox {
    public static func getChecked() -> NSMutableAttributedString? {
        let checkboxText = getCleanChecked()
        checkboxText.append(NSAttributedString(string: " "))

        return checkboxText
    }

    public static func getUnChecked() -> NSMutableAttributedString? {
        let checkboxText = getCleanUnchecked()
        checkboxText.append(NSAttributedString(string: " "))

        return checkboxText
    }

    public static func getCleanUnchecked() -> NSMutableAttributedString {
        let font = NotesTextProcessor.font
        let size = font.pointSize + font.pointSize / 2
        var image: Image
        let attachment = NSTextAttachment()

        if #available(OSX 10.13, iOS 10.0, *) {
            let image = getImage(name: "checkbox_empty")
            attachment.image = image
        } else {
        #if os(OSX)
            image = NSImage(named: "checkbox_empty1012.png")!.resize(to: CGSize(width: size, height: size))!
            let cell = NSTextAttachmentCell(imageCell: image)
            attachment.attachmentCell = cell
        #endif
        }

        attachment.bounds = CGRect(x: CGFloat(0), y: (font.capHeight - size) / 2, width: size, height: size)

        let checkboxText = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))

        checkboxText.addAttribute(.todo, value: 0, range: NSRange(0..<1))

        if #available(OSX 10.13, iOS 10.0, *) {
        } else {
            let offset = (font.capHeight - size) / 2
            checkboxText.addAttribute(.baselineOffset, value: offset, range: NSRange(0..<1))
        }

        let parStyle = NSMutableParagraphStyle()
        parStyle.lineSpacing = CGFloat(UserDefaultsManagement.editorLineSpacing)
        checkboxText.addAttribute(.paragraphStyle, value: parStyle, range: NSRange(0..<1))

        return checkboxText
    }

    public static func getCleanChecked() -> NSMutableAttributedString {
        let font = NotesTextProcessor.font
        let size = font.pointSize + font.pointSize / 2
        var image: Image
        let attachment = NSTextAttachment()

        if #available(OSX 10.13, iOS 10.0, *) {
            image = getImage(name: "checkbox")
            attachment.image = image
        } else {
        #if os(OSX)
            image = NSImage(named: "checkbox1012.png")!.resize(to: CGSize(width: size, height: size))!
            let cell = NSTextAttachmentCell(imageCell: image)
            attachment.attachmentCell = cell
        #endif
        }

        attachment.bounds = CGRect(x: CGFloat(0), y: (font.capHeight - size) / 2, width: size, height: size)

        let checkboxText = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))

        checkboxText.addAttribute(.todo, value: 1, range: NSRange(0..<1))

        if #available(OSX 10.13, iOS 10.0, *) {
        } else {
            let offset = (font.capHeight - size) / 2
            checkboxText.addAttribute(.baselineOffset, value: offset, range: NSRange(0..<1))
        }

        let parStyle = NSMutableParagraphStyle()
        parStyle.lineSpacing = CGFloat(UserDefaultsManagement.editorLineSpacing)
        checkboxText.addAttribute(.paragraphStyle, value: parStyle, range: NSRange(0..<1))

        return checkboxText
    }

    public static func getImage(name: String) -> Image {
        var name = name

        #if os(OSX)
            if name == "checkbox" {
                if #available(OSX 10.15, *) {
                    name = "checkbox_new"
                } else {
                    name = "checkbox_flipped"
                }
            }
            return NSImage(named: name)!
        #else
            var night = String()

            if NightNight.theme == .night {
                night = "_white"
            }

            return UIImage(named: "\(name)\(night).png")!
        #endif
    }
}
