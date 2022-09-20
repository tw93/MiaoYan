import Foundation

extension Date {
    func toMillis() -> Int64! {
        Int64(timeIntervalSince1970 * 1000)
    }

    static func getCurrentFormattedDate() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"

        return dateFormatter.string(from: Date())
    }
}
