//
//  ColorHexTests.swift
//  PlannrTests
//
//  Tests for the Color(hex:) / Color.toHex() helpers used to persist class and
//  event colors.
//

import XCTest
import SwiftUI
@testable import Plannr

final class ColorHexTests: XCTestCase {

    func testSixDigitHexRoundTrips() {
        XCTAssertEqual(Color(hex: "FF5733").toHex(), "FF5733")
        XCTAssertEqual(Color(hex: "007AFF").toHex(), "007AFF")
        XCTAssertEqual(Color(hex: "000000").toHex(), "000000")
        XCTAssertEqual(Color(hex: "FFFFFF").toHex(), "FFFFFF")
    }

    func testLeadingHashIsIgnored() {
        XCTAssertEqual(Color(hex: "#34C759").toHex(), "34C759")
    }

    func testEightDigitHexReadsRgbFromLeadingBytes() {
        // The 8-digit path takes R,G,B from the first three bytes (4th is alpha),
        // so a trailing FF alpha leaves the visible color unchanged.
        XCTAssertEqual(Color(hex: "FF5733FF").toHex(), "FF5733")
    }

    func testGarbageHexFallsBackToBlack() {
        XCTAssertEqual(Color(hex: "not-a-color").toHex(), "000000")
        XCTAssertEqual(Color(hex: "").toHex(), "000000")
    }

    func testToHexHandlesNonRGBColorsWithoutCrashing() {
        // Regression: grayscale colors have < 3 cgColor components and used to
        // crash toHex(). getRed(...) normalizes them.
        XCTAssertEqual(Color.white.toHex(), "FFFFFF")
        XCTAssertEqual(Color.black.toHex(), "000000")
        XCTAssertFalse(Color.gray.toHex().isEmpty)
    }
}
