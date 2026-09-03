//
//  SettingsManager.swift
//  Plannr
//
//  App-wide user preferences (term dates, reminders, sync behavior, notifications).
//

import Foundation

/// How long a term runs, used to derive an end date from the start date.
enum TermSystem: String, CaseIterable, Identifiable {
    case quarter
    case semester
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quarter:  return "Quarter"
        case .semester: return "Semester"
        case .custom:   return "Custom"
        }
    }

    /// Weeks from the start date to the term's end. `nil` for `.custom`, where
    /// the user sets an explicit end date instead.
    var weeks: Int? {
        switch self {
        case .quarter:  return 10
        case .semester: return 16
        case .custom:   return nil
        }
    }

    /// A sensible starting length in weeks for a term of this system — used as
    /// the default the user can then adjust.
    var defaultWeeks: Int {
        switch self {
        case .quarter:  return 10
        case .semester: return 16
        case .custom:   return 12
        }
    }
}

/// "Fall 2026" from a start month + year. Quarter systems distinguish Winter;
/// semester systems fold Winter into Spring. Empty string when `startDate` is nil.
func termSeasonLabel(startDate: Date?, system: TermSystem, calendar: Calendar = .current) -> String {
    guard let startDate else { return "" }
    let month = calendar.component(.month, from: startDate)
    let year = calendar.component(.year, from: startDate)
    let season: String
    switch system {
    case .semester:
        season = (1...5).contains(month) ? "Spring" : (6...7).contains(month) ? "Summer" : "Fall"
    case .quarter, .custom:
        switch month {
        case 1...3: season = "Winter"
        case 4...5: season = "Spring"
        case 6...8: season = "Summer"
        default:    season = "Fall"
        }
    }
    return "\(season) \(year)"
}

struct TermSettings: Equatable {
    var label: String = ""
    var startDate: Date?
    var endDate: Date?
    var system: TermSystem = .quarter

    /// The term's end: an explicit `endDate` when set, otherwise
    /// `startDate` + the system's week count. `nil` when neither is available.
    func resolvedEndDate(calendar: Calendar = .current) -> Date? {
        if let endDate { return endDate }
        guard let startDate, let weeks = system.weeks else { return nil }
        return calendar.date(byAdding: .day, value: weeks * 7, to: startDate)
    }

    /// The user's label, or one derived from the start month ("Fall 2026") when
    /// they haven't typed one. Empty when there's no start date to derive from.
    func displayLabel(calendar: Calendar = .current) -> String {
        let typed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return termSeasonLabel(startDate: startDate, system: system, calendar: calendar)
    }
}

extension TermSystem: Codable {}

extension TermSettings: Codable {
    private enum CodingKeys: String, CodingKey { case label, startDate, endDate, system }

    /// Tolerant decode so a blob written before `system` existed still loads
    /// (older installs would otherwise fall back to a blank term).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        system = try c.decodeIfPresent(TermSystem.self, forKey: .system) ?? .quarter
    }
}

/// -1 means "use Google Calendar's default reminders" (no override sent to the backend).
let reminderLeadTimeOptions: [Int] = [-1, 0, 1, 2, 3, 5, 7]

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var term: TermSettings {
        didSet { saveTerm() }
    }
    @Published var reminderLeadTimeDays: Int {
        didSet { UserDefaults.standard.set(reminderLeadTimeDays, forKey: Keys.reminderLeadTimeDays) }
    }
    @Published var autoSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(autoSyncEnabled, forKey: Keys.autoSyncEnabled) }
    }
    /// When on, a newly added class that has a schedule (typed in, or filled in
    /// by the syllabus parser) turns on "Add class meetings to Google Calendar"
    /// automatically. Existing classes are left alone. Off by default.
    @Published var autoSyncClassMeetings: Bool {
        didSet { UserDefaults.standard.set(autoSyncClassMeetings, forKey: Keys.autoSyncClassMeetings) }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }
    /// Whether recurring class meetings (and final exams) show up in the Week at
    /// a Glance list alongside assignments. Off by default — that list is about
    /// deadlines.
    @Published var showClassMeetingsInWeekView: Bool {
        didSet { UserDefaults.standard.set(showClassMeetingsInWeekView, forKey: Keys.showClassMeetingsInWeekView) }
    }
    /// Whether class meetings / final exams appear in the Calendar tab (grid dots
    /// + the day and upcoming lists). Off by default.
    @Published var showClassMeetingsInCalendar: Bool {
        didSet { UserDefaults.standard.set(showClassMeetingsInCalendar, forKey: Keys.showClassMeetingsInCalendar) }
    }

    /// Minutes-before-event value to send to the backend, or nil to use Google's default reminders.
    var reminderMinutes: Int? {
        reminderLeadTimeDays >= 0 ? reminderLeadTimeDays * 24 * 60 : nil
    }

    private enum Keys {
        static let term = "settings.term"
        static let reminderLeadTimeDays = "settings.reminderLeadTimeDays"
        static let autoSyncEnabled = "settings.autoSyncEnabled"
        static let autoSyncClassMeetings = "settings.autoSyncClassMeetings"
        static let notificationsEnabled = "settings.notificationsEnabled"
        static let showClassMeetingsInWeekView = "settings.showClassMeetingsInWeekView"
        static let showClassMeetingsInCalendar = "settings.showClassMeetingsInCalendar"
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Keys.term),
           let decoded = try? JSONDecoder().decode(TermSettings.self, from: data) {
            term = decoded
        } else {
            term = TermSettings()
        }
        reminderLeadTimeDays = UserDefaults.standard.object(forKey: Keys.reminderLeadTimeDays) as? Int ?? -1
        autoSyncEnabled = UserDefaults.standard.object(forKey: Keys.autoSyncEnabled) as? Bool ?? false
        autoSyncClassMeetings = UserDefaults.standard.object(forKey: Keys.autoSyncClassMeetings) as? Bool ?? false
        notificationsEnabled = UserDefaults.standard.object(forKey: Keys.notificationsEnabled) as? Bool ?? false
        showClassMeetingsInWeekView = UserDefaults.standard.object(forKey: Keys.showClassMeetingsInWeekView) as? Bool ?? false
        showClassMeetingsInCalendar = UserDefaults.standard.object(forKey: Keys.showClassMeetingsInCalendar) as? Bool ?? false
    }

    private func saveTerm() {
        if let encoded = try? JSONEncoder().encode(term) {
            UserDefaults.standard.set(encoded, forKey: Keys.term)
        }
    }

    /// Reset all preferences to their defaults (used when an account is deleted).
    func resetToDefaults() {
        term = TermSettings()
        reminderLeadTimeDays = -1
        autoSyncEnabled = false
        autoSyncClassMeetings = false
        notificationsEnabled = false
        showClassMeetingsInWeekView = false
        showClassMeetingsInCalendar = false
    }
}
