//
//  ClassManagerTests.swift
//  PlannrTests
//
//  ClassManager's array operations and the non-guest persistence round-trip.
//

import XCTest
@testable import Plannr

final class ClassManagerTests: XCTestCase {

    private let persistenceKey = "savedClasses"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: persistenceKey)
        super.tearDown()
    }

    // MARK: - In-memory operations (guest instance — no persistence side effects)

    func testAddRemoveUpdate() {
        let manager = ClassManager(isGuest: true)
        XCTAssertTrue(manager.classes.isEmpty)

        let a = Class(name: "A")
        let b = Class(name: "B")
        manager.addClass(a)
        manager.addClass(b)
        XCTAssertEqual(manager.classes.map(\.name), ["A", "B"])

        var renamed = a
        renamed.name = "A2"
        renamed.status = .active
        manager.updateClass(renamed)
        XCTAssertEqual(manager.classes.first(where: { $0.id == a.id })?.name, "A2")
        XCTAssertEqual(manager.classes.first(where: { $0.id == a.id })?.status, .active)

        manager.removeClass(b)
        XCTAssertEqual(manager.classes.map(\.name), ["A2"])

        manager.removeClassByID(a.id)
        XCTAssertTrue(manager.classes.isEmpty)
    }

    func testUpdateUnknownClassIsNoOp() {
        let manager = ClassManager(isGuest: true)
        manager.addClass(Class(name: "A"))
        manager.updateClass(Class(name: "Ghost"))   // different id
        XCTAssertEqual(manager.classes.map(\.name), ["A"])
    }

    func testClearAllData() {
        let manager = ClassManager(isGuest: true)
        manager.addClass(Class(name: "A"))
        manager.clearAllData()
        XCTAssertTrue(manager.classes.isEmpty)
    }

    // MARK: - Persistence (non-guest)

    func testNonGuestClassesSurviveANewInstance() {
        UserDefaults.standard.removeObject(forKey: persistenceKey)

        let writer = ClassManager(isGuest: false)
        var cls = Class(name: "Persisted", schedule: "MWF", colorHex: "34C759", status: .active)
        cls.meetingEventIds = ["m-1"]
        writer.addClass(cls)

        let reader = ClassManager(isGuest: false)   // loads from UserDefaults in init
        XCTAssertEqual(reader.classes.map(\.name), ["Persisted"])
        XCTAssertEqual(reader.classes.first?.colorHex, "34C759")
        XCTAssertEqual(reader.classes.first?.meetingEventIds, ["m-1"])

        reader.clearAllData()
        XCTAssertTrue(ClassManager(isGuest: false).classes.isEmpty)
    }

    func testGuestInstanceDoesNotPersist() {
        UserDefaults.standard.removeObject(forKey: persistenceKey)
        let guest = ClassManager(isGuest: true)
        guest.addClass(Class(name: "GuestOnly"))
        XCTAssertNil(UserDefaults.standard.data(forKey: persistenceKey),
                     "guest classes must not be written to disk")
    }
}
