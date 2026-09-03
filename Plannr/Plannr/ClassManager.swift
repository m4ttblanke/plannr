//
//  ClassManager.swift
//  Plannr
//
//  Created by Divya Subramonian on 2/12/26.
//

import Foundation
import SwiftUI

enum ClassStatus: String, Codable {
    case noSyllabus = "NO_SYLLABUS"
    case active     = "ACTIVE"
    case inactive   = "INACTIVE"
}

struct SyncSession: Identifiable, Codable {
    let id: UUID
    let date: Date
    let events: [CalendarEvent]

    init(date: Date = Date(), events: [CalendarEvent]) {
        self.id = UUID()
        self.date = date
        self.events = events
    }
}

class ClassManager: ObservableObject {
    @Published var classes: [Class] = []

    /// The pre-scoping, device-wide key. Kept only so a one-time migration can
    /// hand its contents to the first account that signs in after this version.
    static let legacyKey = "savedClasses"

    /// Where this instance persists — `"savedClasses.<account-token>"` for a
    /// signed-in user, `legacyKey` for the unscoped fallback (previews/tests),
    /// or `nil` for a guest (nothing is written).
    private let storageKey: String?

    /// - Parameters:
    ///   - isGuest: guest session — classes live only in memory.
    ///   - accountEmail: the signed-in Google account. Its classes are stored
    ///     under a key derived from the email, so a different account on the
    ///     same device starts from an empty list.
    init(isGuest: Bool = false, accountEmail: String? = nil) {
        if isGuest {
            self.storageKey = nil
        } else if let email = accountEmail, !email.isEmpty {
            self.storageKey = "savedClasses.\(AccountScope.token(forEmail: email))"
        } else {
            self.storageKey = Self.legacyKey
        }

        guard let storageKey else { return }

        // One-time migration: before per-account scoping there was a single
        // device-wide blob. Give it to whichever account runs first, then drop
        // the legacy key so no one else inherits it.
        if storageKey != Self.legacyKey {
            let defaults = UserDefaults.standard
            if defaults.data(forKey: storageKey) == nil,
               let legacy = defaults.data(forKey: Self.legacyKey) {
                defaults.set(legacy, forKey: storageKey)
                defaults.removeObject(forKey: Self.legacyKey)
            }
        }
        loadClasses()
    }

    func addClass(_ newClass: Class) {
        classes.append(newClass)
        saveClasses()
    }

    func removeClass(_ classToRemove: Class) {
        classes.removeAll { $0.id == classToRemove.id }
        saveClasses()
    }

    func removeClassByID(_ id: UUID) {
        classes.removeAll { $0.id == id }
        saveClasses()
    }

    func updateClass(_ updatedClass: Class) {
        if let index = classes.firstIndex(where: { $0.id == updatedClass.id }) {
            classes[index] = updatedClass
            saveClasses()
        }
    }

    /// Wipe this account's locally stored classes (used when a user deletes their
    /// account).
    func clearAllData() {
        classes = []
        guard let storageKey else { return }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: Self.legacyKey)
    }

    private func saveClasses() {
        guard let storageKey else { return }
        if let encoded = try? JSONEncoder().encode(classes) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func loadClasses() {
        guard let storageKey else { return }
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Class].self, from: data) {
            classes = decoded
        }
    }
}

// Class model
struct Class: Identifiable, Codable, Hashable {
    static func == (lhs: Class, rhs: Class) -> Bool {
        lhs.id == rhs.id
            && lhs.colorHex == rhs.colorHex
            && lhs.name == rhs.name
            && lhs.schedule == rhs.schedule
            && lhs.status == rhs.status
            && lhs.hasUnsyncedChanges == rhs.hasUnsyncedChanges
            && lhs.events.count == rhs.events.count
            && lhs.syncHistory.count == rhs.syncHistory.count
            && lhs.structuredSchedule == rhs.structuredSchedule
            && lhs.meetingSyncEnabled == rhs.meetingSyncEnabled
            && lhs.meetingEventIds == rhs.meetingEventIds
            && lhs.termID == rhs.termID
            && lhs.isSample == rhs.isSample
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(colorHex)
        hasher.combine(status)
    }
    let id: UUID
    var name: String
    var schedule: String
    var colorHex: String
    var events: [CalendarEvent]
    var status: ClassStatus
    var googleCalendarId: String?
    var lastSynced: Date?
    var endDate: Date?
    var hasUnsyncedChanges: Bool
    var syncHistory: [SyncSession]
    /// Structured weekly meeting schedule (days + times). `schedule` is its
    /// display string; this is what drives calendar recurrence.
    var structuredSchedule: ClassSchedule?
    /// Whether the class's recurring meetings are pushed to Google Calendar.
    var meetingSyncEnabled: Bool
    /// Google Calendar event ids for the recurring meeting events (one per
    /// pattern: lecture, section). Kept so they can be updated or removed.
    var meetingEventIds: [String]
    /// The term folder this class belongs to, or nil when unfiled.
    var termID: UUID?
    /// The throwaway class behind the "Try a sample syllabus" walkthrough. Never
    /// touches Google Calendar and is deleted when the tour ends.
    var isSample: Bool = false

    var color: Color {
        get { Color(hex: colorHex) }
        set { colorHex = newValue.toHex() }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, schedule, colorHex, events, status, googleCalendarId, lastSynced, endDate
        case hasUnsyncedChanges, syncHistory, structuredSchedule, meetingSyncEnabled, meetingEventIds, termID
        case isSample
    }

    init(
        name: String,
        schedule: String = "",
        colorHex: String = "007AFF",
        events: [CalendarEvent] = [],
        status: ClassStatus = .noSyllabus,
        googleCalendarId: String? = nil,
        lastSynced: Date? = nil,
        endDate: Date? = nil,
        syncHistory: [SyncSession] = [],
        hasUnsyncedChanges: Bool = false,
        structuredSchedule: ClassSchedule? = nil,
        meetingSyncEnabled: Bool = false,
        meetingEventIds: [String] = [],
        termID: UUID? = nil,
        isSample: Bool = false
    ) {
        self.init(
            id: UUID(), name: name, schedule: schedule, colorHex: colorHex, events: events,
            status: status, googleCalendarId: googleCalendarId, lastSynced: lastSynced,
            endDate: endDate, syncHistory: syncHistory, hasUnsyncedChanges: hasUnsyncedChanges,
            structuredSchedule: structuredSchedule, meetingSyncEnabled: meetingSyncEnabled,
            meetingEventIds: meetingEventIds, termID: termID, isSample: isSample
        )
    }

    init(
        id: UUID,
        name: String,
        schedule: String = "",
        colorHex: String = "007AFF",
        events: [CalendarEvent] = [],
        status: ClassStatus = .noSyllabus,
        googleCalendarId: String? = nil,
        lastSynced: Date? = nil,
        endDate: Date? = nil,
        syncHistory: [SyncSession] = [],
        hasUnsyncedChanges: Bool = false,
        structuredSchedule: ClassSchedule? = nil,
        meetingSyncEnabled: Bool = false,
        meetingEventIds: [String] = [],
        termID: UUID? = nil,
        isSample: Bool = false
    ) {
        self.id = id
        self.name = name
        self.schedule = schedule
        self.colorHex = colorHex
        self.events = events
        self.status = status
        self.googleCalendarId = googleCalendarId
        self.lastSynced = lastSynced
        self.endDate = endDate
        self.syncHistory = syncHistory
        self.hasUnsyncedChanges = hasUnsyncedChanges
        self.structuredSchedule = structuredSchedule
        self.meetingSyncEnabled = meetingSyncEnabled
        self.meetingEventIds = meetingEventIds
        self.termID = termID
        self.isSample = isSample
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        schedule = try container.decodeIfPresent(String.self, forKey: .schedule) ?? ""
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "007AFF"
        events = try container.decodeIfPresent([CalendarEvent].self, forKey: .events) ?? []
        status = try container.decodeIfPresent(ClassStatus.self, forKey: .status) ?? .noSyllabus
        googleCalendarId = try container.decodeIfPresent(String.self, forKey: .googleCalendarId)
        lastSynced = try container.decodeIfPresent(Date.self, forKey: .lastSynced)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        syncHistory = try container.decodeIfPresent([SyncSession].self, forKey: .syncHistory) ?? []
        hasUnsyncedChanges = try container.decodeIfPresent(Bool.self, forKey: .hasUnsyncedChanges) ?? false
        structuredSchedule = try container.decodeIfPresent(ClassSchedule.self, forKey: .structuredSchedule)
        meetingSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .meetingSyncEnabled) ?? false
        meetingEventIds = try container.decodeIfPresent([String].self, forKey: .meetingEventIds) ?? []
        termID = try container.decodeIfPresent(UUID.self, forKey: .termID)
        isSample = try container.decodeIfPresent(Bool.self, forKey: .isSample) ?? false
    }
}
