import AppKit
import Cocoa

class NoteRowView: NSTableRowView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 选中的时候不出现分割线
        if isSelected { return }

        // 选中的行上一个分割线也不出现
        if let tableView = superview as? NSTableView,
           let selectedRow = tableView.selectedRowIndexes.first, selectedRow > 0,
           let previousRow = tableView.rowView(atRow: selectedRow - 1, makeIfNecessary: false),
           self == previousRow {
            return
        }

        drawSeparator(in: dirtyRect)
    }

    override var isEmphasized: Bool {
        set {}
        get {
            false
        }
    }
}
