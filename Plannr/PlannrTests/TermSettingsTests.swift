//
//  TermSettingsTests.swift
//  PlannrTests
//
//  TermSettings: system-derived end date, auto label, and tolerant decoding.
//

import XCTest
@testable import Plannr

final class TermSettingsTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: - resolvedEndDate

    func testQuarterEndsTenWeeksAfterStart() {
        var t = TermSettings()
        t.system = .quarter
        t.startDate = date(2026, 9, 21)
        XCTAssertEqual(t.resolvedEndDate(calendar: calendar), date(2026, 11, 30))  // +70 days
    }

    func testSemesterEndsSixteenWeeksAfterStart() {
        var t = TermSettings()
        t.system = .semester
        t.startDate = date(2026, 1, 12)
        XCTAssertEqual(t.resolvedEndDate(calendar: calendar), date(2026, 5, 4))    // +112 days
    }

    func testCustomUsesTheExplicitEndDate() {
        var t = TermSettings()
        t.system = .custom
        t.startDate = date(2026, 6, 1)
        t.endDate = date(2026, 7, 15)
        XCTAssertEqual(t.resolvedEndDate(calendar: calendar), date(2026, 7, 15))
    }

    func testCustomWithoutAnEndDateResolvesToNil() {
        var t = TermSettings()
        t.system = .custom
        t.startDate = date(2026, 6, 1)
        XCTAssertNil(t.resolvedEndDate(calendar: calendar))
    }

    func testAnExplicitEndDateWinsOverTheSystemDefault() {
        var t = TermSettings()
        t.system = .quarter
        t.startDate = date(2026, 9, 21)
        t.endDate = date(2026, 12, 18)
        XCTAssertEqual(t.resolvedEndDate(calendar: calendar), date(2026, 12, 18))
    }

    func testNoStartDateResolvesToNil() {
        XCTAssertNil(TermSettings().resolvedEndDate(calendar: calendar))
    }

    // MARK: - displayLabel

    func testTypedLabelAlwaysWins() {
        var t = TermSettings()
        t.label = "  My Term  "
        t.startDate = date(2026, 9, 1)
        XCTAssertEqual(t.displayLabel(calendar: calendar), "My Term")
    }

    func testQuarterLabelDerivesSeasonFromStartMonth() {
        func label(month: Int) -> String {
            var t = TermSettings(); t.system = .quarter; t.startDate = date(2026, month, 5)
            return t.displayLabel(calendar: calendar)
        }
        XCTAssertEqual(label(month: 1), "Winter 2026")
        XCTAssertEqual(label(month: 4), "Spring 2026")
        XCTAssertEqual(label(month: 7), "Summer 2026")
        XCTAssertEqual(label(month: 9), "Fall 2026")
    }

    func testSemesterLabelHasNoWinter() {
        func label(month: Int) -> String {
            var t = TermSettings(); t.system = .semester; t.startDate = date(2027, month, 5)
            return t.displayLabel(calendar: calendar)
        }
        XCTAssertEqual(label(month: 1), "Spring 2027")
        XCTAssertEqual(label(month: 6), "Summer 2027")
        XCTAssertEqual(label(month: 8), "Fall 2027")
    }

    func testLabelIsEmptyWithoutAStartDate() {
        XCTAssertEqual(TermSettings().displayLabel(calendar: calendar), "")
    }

    // MARK: - Codable

    func testRoundTripPreservesSystem() throws {
        var t = TermSettings()
        t.label = "Fall 2026"
        t.startDate = date(2026, 9, 21)
        t.system = .semester
        let back = try JSONDecoder().decode(TermSettings.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back, t)
        XCTAssertEqual(back.system, .semester)
    }

    func testLegacyBlobWithoutSystemDecodesAsQuarterAndKeepsDates() throws {
        // Take a real encoding and strip `system` to simulate a pre-upgrade blob.
        var seed = TermSettings()
        seed.label = "Fall 2026"
        seed.startDate = date(2026, 9, 21)
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(seed)) as! [String: Any]
        dict.removeValue(forKey: "system")
        let data = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(TermSettings.self, from: data)
        XCTAssertEqual(decoded.system, .quarter)
        XCTAssertEqual(decoded.label, "Fall 2026")
        XCTAssertEqual(decoded.startDate, date(2026, 9, 21))
    }
}
