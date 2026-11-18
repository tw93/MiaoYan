import Foundation

/// A note's date as a list row shows it, the same on Mac, iPhone and iPad: the
/// time today, then Yesterday, the day within this year, the full date before
/// that. The Mac list had printed `2026/11/18 22:08` on every row, a column of
/// digits beside the iPhone's `10月11日` (2026-11-18).
public enum NoteListDate {
    public static func short(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.dateTimeStyle = .named
            formatter.formattingContext = .beginningOfSentence
            return formatter.localizedString(from: DateComponents(day: -1))
        }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(style.month().day())
        }
        return date.formatted(style.year().month().day())
    }
}
