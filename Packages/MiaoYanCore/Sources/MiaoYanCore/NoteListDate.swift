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
        let words = subtags(of: language).filter { !isRegion($0) }.joined(separator: "-")
        let region = region(of: system.identifier).map { "_" + $0 } ?? ""
        // `j` is the hour as the system shows it, the person's own 12 or
        // 24-hour choice included; `H` and `k` are the 24-hour letters.
        let hour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: system) ?? ""
        let cycle = hour.contains("H") || hour.contains("k") ? "h23" : "h12"
        return Locale(identifier: words + region + "@hours=" + cycle)
    }

    /// The parts of a locale identifier before its keywords (`zh`, `Hans`,
    /// `CN` in `zh-Hans_CN@calendar=…`). Read from the text: the Foundation
    /// calls that name them are deprecated on iOS 16 or missing on macOS 12,
    /// and this package builds for both.
    private static func subtags(of identifier: String) -> [String] {
        identifier.prefix { $0 != "@" }.split { $0 == "_" || $0 == "-" }.map(String.init)
    }

    /// The region a system locale formats for: its Region setting when the
    /// identifier carries one apart from the language's own (`US` in
    /// `en_GB@rg=uszzzz`, British English on a Mac set to the United
    /// States), else its region subtag.
    private static func region(of identifier: String) -> String? {
        if let keywords = identifier.split(separator: "@").dropFirst().first,
            let override = keywords.split(separator: ";").first(where: { $0.hasPrefix("rg=") })
        {
            let code = override.dropFirst(3).prefix(2).uppercased()
            if isRegion(code) { return code }
        }
        return subtags(of: identifier).dropFirst().first(where: isRegion)
    }

    /// Two capitals (`CN`) or three digits (`419`); a script has four letters.
    private static func isRegion(_ tag: String) -> Bool {
        (tag.count == 2 && tag.allSatisfy { $0.isLetter && $0.isUppercase }) || (tag.count == 3 && tag.allSatisfy(\.isNumber))
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
