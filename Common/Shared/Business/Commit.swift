import Foundation

class Commit {
    private var date: String?
    private var hash: String

    init(hash: String) {
        self.hash = hash
    }

    public func setDate(date: String) {
        self.date = date
    }

    public func getDate() -> String? {
        return date
    }

    public func getHash() -> String {
        return hash
    }
}
