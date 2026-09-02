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

    private func key(for email: String) -> String {
        "savedClasses.\(AccountScope.token(forEmail: email))"
    }

    override func setUp() {
        super.setUp()
        clearStores()
    }

    override func tearDown() {
        clearStores()
        super.tearDown()
    }

    private func clearStores() {
        let d = UserDefaults.standard
        for k in d.dictionaryRepresentation().keys where k == persistenceKey || k.hasPrefix("savedClasses.") {
            d.removeObject(forKey: k)
        }
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

    // MARK: - Per-account scoping

    func testTwoAccountsHaveSeparateStores() {
        let a = ClassManager(accountEmail: "alice@example.com")
        a.addClass(Class(name: "Alice's class"))

        let b = ClassManager(accountEmail: "bob@example.com")
        XCTAssertTrue(b.classes.isEmpty, "a different account starts empty")
        b.addClass(Class(name: "Bob's class"))

        XCTAssertEqual(ClassManager(accountEmail: "alice@example.com").classes.map(\.name), ["Alice's class"])
        XCTAssertEqual(ClassManager(accountEmail: "bob@example.com").classes.map(\.name), ["Bob's class"])
        // The legacy device-wide key is untouched by scoped instances.
        XCTAssertNil(UserDefaults.standard.data(forKey: persistenceKey))
    }

    func testAccountEmailIsCaseInsensitive() {
        ClassManager(accountEmail: "Sam@Example.com").addClass(Class(name: "Sam's"))
        XCTAssertEqual(ClassManager(accountEmail: "sam@example.com").classes.map(\.name), ["Sam's"])
    }

    func testGuestIgnoresAccountEmailAndNeverPersists() {
        let guest = ClassManager(isGuest: true, accountEmail: "ghost@example.com")
        guest.addClass(Class(name: "Ephemeral"))
        XCTAssertNil(UserDefaults.standard.data(forKey: key(for: "ghost@example.com")))
        XCTAssertNil(UserDefaults.standard.data(forKey: persistenceKey))
    }

    // MARK: - One-time legacy migration

    func testLegacyBlobMigratesToFirstAccountThenIsGone() {
        // Simulate a pre-scoping install: a device-wide blob under "savedClasses".
        let legacyBlob = try! JSONEncoder().encode([Class(name: "Pre-existing")])
        UserDefaults.standard.set(legacyBlob, forKey: persistenceKey)

        // First account to run inherits it...
        let first = ClassManager(accountEmail: "first@example.com")
        XCTAssertEqual(first.classes.map(\.name), ["Pre-existing"])
        XCTAssertNil(UserDefaults.standard.data(forKey: persistenceKey), "legacy key is consumed")
        XCTAssertNotNil(UserDefaults.standard.data(forKey: key(for: "first@example.com")))

        // ...and no one else does.
        XCTAssertTrue(ClassManager(accountEmail: "second@example.com").classes.isEmpty)
    }

    func testLegacyMigrationDoesNotClobberAnExistingScopedStore() {
        ClassManager(accountEmail: "keep@example.com").addClass(Class(name: "Mine"))
        UserDefaults.standard.set(try! JSONEncoder().encode([Class(name: "Legacy")]), forKey: persistenceKey)

        let reopened = ClassManager(accountEmail: "keep@example.com")
        XCTAssertEqual(reopened.classes.map(\.name), ["Mine"], "existing scoped data wins")
        XCTAssertNotNil(UserDefaults.standard.data(forKey: persistenceKey), "legacy key left for a fresh account")
    }
}
