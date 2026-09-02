//
//  ParsePhaseTests.swift
//  PlannrTests
//
//  The time-based phase mapping shown while a syllabus uploads.
//

import XCTest
@testable import Plannr

final class ParsePhaseTests: XCTestCase {

    func testStartsOnWakingServer() {
        XCTAssertEqual(ParsePhase.phase(forElapsed: 0), .wakingServer)
        XCTAssertEqual(ParsePhase.phase(forElapsed: 5.9), .wakingServer)
    }

    func testAdvancesThroughTheThreePhases() {
        XCTAssertEqual(ParsePhase.phase(forElapsed: 6), .reading)
        XCTAssertEqual(ParsePhase.phase(forElapsed: 14.5), .reading)
        XCTAssertEqual(ParsePhase.phase(forElapsed: 15), .extracting)
    }

    func testTheFinalPhaseIsSticky() {
        XCTAssertEqual(ParsePhase.phase(forElapsed: 30), .extracting)
        XCTAssertEqual(ParsePhase.phase(forElapsed: 120), .extracting)
    }

    func testNegativeElapsedFallsBackToTheFirstPhase() {
        XCTAssertEqual(ParsePhase.phase(forElapsed: -3), .wakingServer)
    }

    func testPhasesAreInAscendingStartOrderAndAllLabelled() {
        let starts = ParsePhase.allCases.map(\.startsAt)
        XCTAssertEqual(starts, starts.sorted())
        XCTAssertEqual(ParsePhase.allCases.first?.startsAt, 0)
        XCTAssertTrue(ParsePhase.allCases.allSatisfy { !$0.message.isEmpty })
    }
}
