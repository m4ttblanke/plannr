//
//  TermStoreTests.swift
//  PlannrTests
//
//  Per-account persistence + active-term resolution for TermStore.
//

import XCTest
@testable import Plannr

final class TermStoreTests: XCTestCase {

    override func setUp() { super.setUp(); clear() }
    override func tearDown() { clear(); super.tearDown() }

    private func clear() {
        let d = UserDefaults.standard
        for k in d.dictionaryRepresentation().keys where k.hasPrefix("terms.") {
            d.removeObject(forKey: k)
        }
    }

    // MARK: - Persistence

    func testTermsSurviveANewInstanceForTheSameAccount() {
        let a = TermStore(accountEmail: "alice@example.com")
        let term = Term(name: "Fall 2026")
        a.add(term)
        a.activeTermID = term.id

        let reopened = TermStore(accountEmail: "alice@example.com")
        XCTAssertEqual(reopened.terms.map(\.name), ["Fall 2026"])
        XCTAssertEqual(reopened.activeTermID, term.id)
    }

    func testTwoAccountsAreIsolated() {
        TermStore(accountEmail: "alice@example.com").add(Term(name: "Alice term"))
        let bob = TermStore(accountEmail: "bob@example.com")
        XCTAssertTrue(bob.terms.isEmpty)
    }

    func testGuestDoesNotPersist() {
        let guest = TermStore(isGuest: true)
        guest.add(Term(name: "Ephemeral"))
        XCTAssertTrue(TermStore(isGuest: true).terms.isEmpty)
        XCTAssertNil(UserDefaults.standard.data(forKey: "\(TermStore.listKeyPrefix)default"))
    }

    func testEmailIsCaseInsensitive() {
        TermStore(accountEmail: "Sam@Example.com").add(Term(name: "Sam's"))
        XCTAssertEqual(TermStore(accountEmail: "sam@example.com").terms.map(\.name), ["Sam's"])
    }

    // MARK: - CRUD

    func testUpdateAndRemove() {
        let store = TermStore(accountEmail: "x@e.com")
        var term = Term(name: "One")
        store.add(term)
        term.name = "Renamed"
        store.update(term)
        XCTAssertEqual(store.terms.first?.name, "Renamed")

        store.activeTermID = term.id
        store.remove(id: term.id)
        XCTAssertTrue(store.terms.isEmpty)
        XCTAssertNil(store.activeTermID, "removing the active term clears the pointer")
    }

    // MARK: - activeTerm resolution

    func testActiveTermPrefersTheExplicitChoice() {
        let store = TermStore(accountEmail: "x@e.com")
        let past = Term(name: "Past", startDate: Date().addingTimeInterval(-400 * 86_400))
        let now = Term(name: "Now", startDate: Date().addingTimeInterval(-7 * 86_400))
        store.add(past); store.add(now)
        store.activeTermID = past.id
        XCTAssertEqual(store.activeTerm?.id, past.id)
    }

    func testActiveTermFallsBackToTheTermContainingToday() {
        let store = TermStore(accountEmail: "x@e.com")
        store.add(Term(name: "Old", startDate: Date().addingTimeInterval(-400 * 86_400)))
        let current = Term(name: "Current", startDate: Date().addingTimeInterval(-7 * 86_400), system: .quarter)
        store.add(current)
        XCTAssertNil(store.activeTermID)
        XCTAssertEqual(store.activeTerm?.id, current.id)
    }

    func testActiveTermFallsBackToTheMostRecentStart() {
        let store = TermStore(accountEmail: "x@e.com")
        let older = Term(name: "Older", startDate: Date().addingTimeInterval(-800 * 86_400))
        let newer = Term(name: "Newer", startDate: Date().addingTimeInterval(-500 * 86_400))
        store.add(older); store.add(newer)
        XCTAssertEqual(store.activeTerm?.id, newer.id, "no term contains today → most recent start wins")
    }
}
