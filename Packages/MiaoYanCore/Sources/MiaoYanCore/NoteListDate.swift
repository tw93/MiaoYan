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
            return yesterdayWord(locale)
        }
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(style.month().day())
        }
        return date.formatted(style.year().month().day())
    }

    /// The locale for a list whose app speaks `language` on a system set to
    /// `system`: the app's words with the system's region and clock. The Mac
    /// app has its own language, and a locale made from that alone lost both:
    /// an English interface in China or Britain printed `10:06 PM` beside a
    /// menu bar clock reading 22:06, and so did anyone who had switched a
    /// 12-hour region to 24-hour time (2026-11-20). The iPhone app follows the
    /// system's language and passes `Locale.current` as it is.
    public static func displayLocale(language: String, system: Locale = .current) -> Locale {
        let region = NSLocale.Key.countryCode.rawValue
        var parts = Locale.components(fromIdentifier: language)
        if let code = Locale.components(fromIdentifier: system.identifier)[region] { parts[region] = code }
        // `j` is the hour as the system shows it, the person's own 12 or
        // 24-hour choice included; `H` and `k` are the 24-hour letters.
        let hour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: system) ?? ""
        parts["hours"] = hour.contains("H") || hour.contains("k") ? "h23" : "h12"
        return Locale(identifier: Locale.identifier(fromComponents: parts))
    }

    /// The word for yesterday, made once per language: a list scrolling past
    /// notes from yesterday had built a RelativeDateTimeFormatter for every
    /// row (iPhone review, 2026-11-11). NSCache is safe to share across threads.
    private static func yesterdayWord(_ locale: Locale) -> String {
        let key = locale.identifier as NSString
        if let word = yesterdayWords.object(forKey: key) { return word as String }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.formattingContext = .beginningOfSentence
        let word = formatter.localizedString(from: DateComponents(day: -1))
        yesterdayWords.setObject(word as NSString, forKey: key)
        return word
    }

    nonisolated(unsafe) private static let yesterdayWords = NSCache<NSString, NSString>()
}
