//
//  CustomTextStorage+Images.swift
//  FSNotes
//
//  Created by Олександр Глущенко on 9/21/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa
import AVKit

extension NSTextStorage {
    public func loadImage(attachment: NSTextAttachment, url: URL, range: NSRange) {
        EditTextView.imagesLoaderQueue.addOperation {
            guard url.isImage else { return }

            let size = attachment.bounds.size
            let retinaSize = CGSize(width: size.width * 2, height: size.height * 2)
            let image = NoteAttachment.getImage(url: url, size: retinaSize)

            DispatchQueue.main.async {
                let cell = NSTextAttachmentCell(imageCell: image)
                cell.image?.size = size
                attachment.image = nil
                attachment.attachmentCell = cell
                attachment.bounds = NSRect(x: 0, y: 0, width: size.width, height: size.height)

                if let manager = ViewController.shared()?.editArea.layoutManager {
                    if #available(OSX 10.13, *) {
                    } else {
                        if self.mutableString.length >= range.upperBound {
                            manager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                        }
                    }

                    manager.invalidateDisplay(forCharacterRange: range)
                }
            }
        }
    }
}
