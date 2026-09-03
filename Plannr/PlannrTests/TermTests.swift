//
//  TermTests.swift
//  PlannrTests
//
//  The Term model: end date from length, display name, membership, migration seed.
//

import XCTest
@testable import Plannr

final class TermTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: - resolvedEndDate

    func testEndDateIsStartPlusWeeks() {
        let term = Term(name: "Fall", startDate: date(2026, 9, 21), system: .quarter)  // 10 weeks
        XCTAssertEqual(term.resolvedEndDate(calendar: calendar), date(2026, 11, 30))
    }

    func testCustomWeeksDriveTheEndDate() {
        var term = Term(name: "Summer", startDate: date(2026, 6, 22), system: .custom, weeks: 6)
        XCTAssertEqual(term.resolvedEndDate(calendar: calendar), date(2026, 8, 3))
        term.weeks = 8
        XCTAssertEqual(term.resolvedEndDate(calendar: calendar), date(2026, 8, 17))
    }

    func testNoStartDateHasNoEndDate() {
        XCTAssertNil(Term(system: .semester).resolvedEndDate(calendar: calendar))
    }

    func testWeeksDefaultsFromSystemAndNeverGoesBelowOne() {
        XCTAssertEqual(Term(system: .quarter).weeks, 10)
        XCTAssertEqual(Term(system: .semester).weeks, 16)
        XCTAssertEqual(Term(system: .custom, weeks: 0).weeks, 1)
    }

    // MARK: - displayName

    func testDisplayNamePrefersTheTypedName() {
        XCTAssertEqual(Term(name: "  My Term  ", startDate: date(2026, 9, 1)).displayName(calendar: calendar), "My Term")
    }

    func testDisplayNameFallsBackToSeasonThenPlaceholder() {
        XCTAssertEqual(Term(startDate: date(2026, 9, 1), system: .quarter).displayName(calendar: calendar), "Fall 2026")
        XCTAssertEqual(Term(startDate: date(2027, 1, 12), system: .semester).displayName(calendar: calendar), "Spring 2027")
        XCTAssertEqual(Term().displayName(calendar: calendar), "Untitled term")
    }

    // MARK: - contains

    func testContainsIsHalfOpen() {
        let term = Term(startDate: date(2026, 9, 21), system: .quarter)  // ends 2026-11-30
        XCTAssertTrue(term.contains(date(2026, 9, 21), calendar: calendar))
        XCTAssertTrue(term.contains(date(2026, 10, 15), calendar: calendar))
        XCTAssertFalse(term.contains(date(2026, 11, 30), calendar: calendar))  // end is exclusive
        XCTAssertFalse(term.contains(date(2026, 9, 20), calendar: calendar))
    }

    // MARK: - migration seed

    func testSeedingFromLegacyTermSettings() {
        var legacy = TermSettings()
        legacy.label = "Winter 2026"
        legacy.startDate = date(2026, 1, 5)
        legacy.system = .quarter
        let term = Term(seedingFrom: legacy, calendar: calendar)
        XCTAssertEqual(term.name, "Winter 2026")
        XCTAssertEqual(term.startDate, date(2026, 1, 5))
        XCTAssertEqual(term.system, .quarter)
        XCTAssertEqual(term.weeks, 10)
    }

    func testSeedingDerivesWeeksFromAnExplicitEndDate() {
        var legacy = TermSettings()
        legacy.startDate = date(2026, 1, 5)
        legacy.endDate = date(2026, 3, 30)   // ~12 weeks
        legacy.system = .custom
        let term = Term(seedingFrom: legacy, calendar: calendar)
        XCTAssertEqual(term.weeks, 12)
    }

    // MARK: - Codable

    func testRoundTrip() throws {
        let term = Term(name: "T", startDate: date(2026, 9, 1), system: .custom, weeks: 13, autoSyncMeetings: true)
        let back = try JSONDecoder().decode(Term.self, from: JSONEncoder().encode(term))
        XCTAssertEqual(back, term)
    }

    func testTolerantDecodeFillsDefaults() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Bare"}"#
        let term = try JSONDecoder().decode(Term.self, from: Data(json.utf8))
        XCTAssertEqual(term.name, "Bare")
        XCTAssertEqual(term.system, .quarter)
        XCTAssertEqual(term.weeks, 10)
        XCTAssertFalse(term.autoSyncMeetings)
    }
}
