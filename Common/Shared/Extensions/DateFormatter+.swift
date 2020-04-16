import Foundation

public extension DateFormatter {
    func formatDateForDisplay(_ date: Date) -> String {
        dateStyle = .short
        timeStyle = .none
        locale = NSLocale.autoupdatingCurrent
        return string(from: date)
    }

    func formatTimeForDisplay(_ date: Date) -> String {
        dateStyle = .medium
        timeStyle = .short
        locale = NSLocale.autoupdatingCurrent
        return string(from: date)
    }

    func formatForDuplicate(_ date: Date) -> String {
        dateFormat = "yyyyMMddhhmmss"
        return string(from: date)
    }
}
