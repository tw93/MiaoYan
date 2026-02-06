import Foundation

extension Date {
    func toMillis() -> Int64! {
        Int64(timeIntervalSince1970 * 1000)
    }

}

extension DateFormatter {
    public func formatDateForDisplay(_ date: Date) -> String {
        dateStyle = .short
        timeStyle = .none
        locale = NSLocale.autoupdatingCurrent
        return string(from: date)
    }

    public func formatTimeForDisplay(_ date: Date) -> String {
        dateFormat = "yyyy/MM/dd HH:mm"
        return string(from: date)
    }
}
