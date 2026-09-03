//
//  TermStore.swift
//  Plannr
//
//  Per-account persistence for term folders (see AccountScope), mirroring
//  ClassManager. A guest instance keeps everything in memory.
//

import Foundation
import Combine

final class TermStore: ObservableObject {
    @Published private(set) var terms: [Term] = []
    @Published var activeTermID: UUID? {
        didSet { persistActive() }
    }

    static let listKeyPrefix = "terms.list."
    static let activeKeyPrefix = "terms.active."

    private let listKey: String?
    private let activeKey: String?

    init(isGuest: Bool = false, accountEmail: String? = nil) {
        if isGuest {
            listKey = nil
            activeKey = nil
        } else if let email = accountEmail, !email.isEmpty {
            let token = AccountScope.token(forEmail: email)
            listKey = "\(Self.listKeyPrefix)\(token)"
            activeKey = "\(Self.activeKeyPrefix)\(token)"
        } else {
            listKey = "\(Self.listKeyPrefix)default"
            activeKey = "\(Self.activeKeyPrefix)default"
        }

        guard let listKey else { return }
        if let data = UserDefaults.standard.data(forKey: listKey),
           let decoded = try? JSONDecoder().decode([Term].self, from: data) {
            terms = decoded
        }
        if let activeKey,
           let raw = UserDefaults.standard.string(forKey: activeKey),
           let id = UUID(uuidString: raw) {
            activeTermID = id
        }
    }

    // MARK: - CRUD

    func add(_ term: Term) {
        terms.append(term)
        persist()
    }

    func update(_ term: Term) {
        guard let idx = terms.firstIndex(where: { $0.id == term.id }) else { return }
        terms[idx] = term
        persist()
    }

    /// Remove a term. Filing its classes elsewhere is the caller's job.
    func remove(id: UUID) {
        terms.removeAll { $0.id == id }
        if activeTermID == id { activeTermID = nil }
        persist()
    }

    func term(id: UUID?) -> Term? {
        guard let id else { return nil }
        return terms.first { $0.id == id }
    }

    /// The user's chosen active term, or a best guess: the term whose date range
    /// contains today, else the one starting most recently, else the first.
    var activeTerm: Term? {
        if let chosen = term(id: activeTermID) { return chosen }
        if let current = terms.first(where: { $0.contains(Date()) }) { return current }
        return terms.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }.first
    }

    func clearAllData() {
        terms = []
        activeTermID = nil
        guard let listKey else { return }
        UserDefaults.standard.removeObject(forKey: listKey)
        if let activeKey { UserDefaults.standard.removeObject(forKey: activeKey) }
    }

    // MARK: - Persistence

    private func persist() {
        guard let listKey, let encoded = try? JSONEncoder().encode(terms) else { return }
        UserDefaults.standard.set(encoded, forKey: listKey)
    }

    private func persistActive() {
        guard let activeKey else { return }
        if let id = activeTermID {
            UserDefaults.standard.set(id.uuidString, forKey: activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeKey)
        }
    }
}
