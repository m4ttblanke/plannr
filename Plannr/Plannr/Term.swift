//
//  Term.swift
//  Plannr
//
//  A term folder — a named span (quarter / semester / custom length) that
//  classes can be filed into. Persisted per account by `TermStore`. Classes
//  reference one by `Class.termID`; a nil termID means the class is unfiled.
//

import Foundation

struct Term: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var startDate: Date?
    /// Length in weeks — drives the end date. Students know "10 weeks" even
    /// when they don't know the exact end date.
    var weeks: Int
    /// The preset this term came from; only used for the season label.
    var system: TermSystem
    /// When on, a class added to this term starts with meeting sync enabled.
    var autoSyncMeetings: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        startDate: Date? = nil,
        system: TermSystem = .quarter,
        weeks: Int? = nil,
        autoSyncMeetings: Bool = false
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.system = system
        self.weeks = max(1, weeks ?? system.defaultWeeks)
        self.autoSyncMeetings = autoSyncMeetings
    }

    /// Seed a term from the Phase-1 single `TermSettings` blob (the migration).
    init(seedingFrom settings: TermSettings, calendar: Calendar = .current) {
        let weeks: Int
        if let end = settings.endDate, let start = settings.startDate {
            weeks = max(1, calendar.dateComponents([.day], from: start, to: end).day.map { ($0 + 6) / 7 } ?? settings.system.defaultWeeks)
        } else {
            weeks = settings.system.weeks ?? settings.system.defaultWeeks
        }
        self.init(
            name: settings.label,
            startDate: settings.startDate,
            system: settings.system == .custom ? .custom : settings.system,
            weeks: weeks
        )
    }

    /// `startDate` + `weeks`. Nil when there's no start date.
    func resolvedEndDate(calendar: Calendar = .current) -> Date? {
        guard let startDate else { return nil }
        return calendar.date(byAdding: .day, value: max(1, weeks) * 7, to: startDate)
    }

    /// The typed name, or a season label ("Fall 2026") derived from the start.
    /// "Untitled term" when neither is available.
    func displayName(calendar: Calendar = .current) -> String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        let season = termSeasonLabel(startDate: startDate, system: system, calendar: calendar)
        return season.isEmpty ? "Untitled term" : season
    }

    /// Whether `date` falls in `[startDate, end)`.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let startDate, let end = resolvedEndDate(calendar: calendar) else { return false }
        return date >= calendar.startOfDay(for: startDate) && date < end
    }

    enum CodingKeys: String, CodingKey { case id, name, startDate, weeks, system, autoSyncMeetings }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        system = try c.decodeIfPresent(TermSystem.self, forKey: .system) ?? .quarter
        weeks = max(1, try c.decodeIfPresent(Int.self, forKey: .weeks) ?? system.defaultWeeks)
        autoSyncMeetings = try c.decodeIfPresent(Bool.self, forKey: .autoSyncMeetings) ?? false
    }
}
