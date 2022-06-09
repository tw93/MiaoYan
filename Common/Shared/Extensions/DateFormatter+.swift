import Foundation

public extension DateFormatter {
    func formatDateForDisplay(_ date: Date) -> String {
        dateStyle = .short
        timeStyle = .none
        locale = NSLocale.autoupdatingCurrent
        return string(from: date)
    }

    func formatTimeForDisplay(_ date: Date) -> String {
        dateFormat = "yyyy/MM/dd hh:mm"
        return string(from: date)
    }

    func formatForDuplicate(_ date: Date) -> String {
        dateFormat = "yyyyMMddhhmmss"
        return string(from: date)
    }
}
