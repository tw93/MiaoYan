//
//  VerticallyCenteredTextFieldCell.swift
//  MiaoYan
//  Created by Tw93 on 2022/6/24.
//

import AppKit

class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let adjustedFrame = adjusted(frame: cellFrame)
        super.drawInterior(withFrame: adjustedFrame, in: controlView)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let adjustedFrame = adjusted(frame: rect)
        return super.drawingRect(forBounds: adjustedFrame)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        let adjustedFrame = adjusted(frame: rect)
        super.edit(withFrame: adjustedFrame, in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        let adjustedFrame = adjusted(frame: rect)
        super.select(withFrame: adjustedFrame, in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }

    private func adjusted(frame: NSRect) -> NSRect {
        let offset = -5.0
        return frame.insetBy(dx: 0, dy: offset)
    }
}
