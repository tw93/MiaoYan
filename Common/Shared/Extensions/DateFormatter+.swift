import Foundation

public extension DateFormatter {
    func formatDateForDisplay(_ date: Date) -> String {
        dateStyle = .short
        timeStyle = .none
        locale = NSLocale.autoupdatingCurrent
        return string(from: date)
    }

    func formatTimeForDisplay(_ date: Date) -> String {
        dateFormat = "yyyy/MM/dd HH:mm"
        return string(from: date)
    }

    func formatForDuplicate(_ date: Date) -> String {
        dateFormat = "yyyyMMddHHmmss"
        return string(from: date)
    }
}
