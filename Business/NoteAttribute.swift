import Foundation

enum NoteAttribute {
    static let highlight = NSAttributedString.Key(rawValue: "com.tw93.search.highlight")

    static let all = Set<NSAttributedString.Key>([
        highlight
    ])
}
