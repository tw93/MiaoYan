import Foundation

class UndoData: NSObject {
    let string: NSAttributedString
    let range: NSRange

    init(string: NSAttributedString, range: NSRange) {
        self.string = string
        self.range = range
    }
}
