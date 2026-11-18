import Foundation
import XCTest

@testable import MiaoYanCore

final class NoteListDateTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func short(_ value: Date, _ locale: String) -> String {
        NoteListDate.short(value, now: date(2026, 11, 18, 22, 30), calendar: calendar, locale: Locale(identifier: locale))
    }

    func testTodayShowsOnlyTheTime() {
        XCTAssertEqual(short(date(2026, 11, 18, 22, 8), "en_US"), "10:08\u{202F}PM")
        XCTAssertFalse(short(date(2026, 11, 18, 22, 8), "zh_CN").contains("2026"))
        XCTAssertTrue(short(date(2026, 11, 18, 22, 8), "zh_CN").contains("22:08"))
    }

    func testYesterdayIsNamed() {
        XCTAssertEqual(short(date(2026, 11, 17, 9), "en_US"), "Yesterday")
        XCTAssertEqual(short(date(2026, 11, 17, 9), "zh_CN"), "昨天")
    }

    func testThisYearShowsMonthAndDay() {
        XCTAssertEqual(short(date(2026, 10, 11), "zh_CN"), "10月11日")
        XCTAssertEqual(short(date(2026, 10, 11), "en_US"), "Oct 11")
    }

    func testAnEarlierYearKeepsTheYear() {
        XCTAssertEqual(short(date(2025, 3, 2), "zh_CN"), "2025年3月2日")
        XCTAssertTrue(short(date(2025, 3, 2), "en_US").contains("2025"))
    }
}
