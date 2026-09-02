//
//  SettingsManager.swift
//  Plannr
//
//  App-wide user preferences (term dates, reminders, sync behavior, notifications).
//

import Foundation

struct TermSettings: Codable, Equatable {
    var label: String = ""
    var startDate: Date?
    var endDate: Date?
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
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }
    /// Whether recurring class meetings show up in the Week at a Glance list
    /// alongside assignments. Off by default — that list is about deadlines.
    @Published var showClassMeetingsInWeekView: Bool {
        didSet { UserDefaults.standard.set(showClassMeetingsInWeekView, forKey: Keys.showClassMeetingsInWeekView) }
    }

    /// Minutes-before-event value to send to the backend, or nil to use Google's default reminders.
    var reminderMinutes: Int? {
        reminderLeadTimeDays >= 0 ? reminderLeadTimeDays * 24 * 60 : nil
    }

    private enum Keys {
        static let term = "settings.term"
        static let reminderLeadTimeDays = "settings.reminderLeadTimeDays"
        static let autoSyncEnabled = "settings.autoSyncEnabled"
        static let notificationsEnabled = "settings.notificationsEnabled"
        static let showClassMeetingsInWeekView = "settings.showClassMeetingsInWeekView"
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
        notificationsEnabled = UserDefaults.standard.object(forKey: Keys.notificationsEnabled) as? Bool ?? false
        showClassMeetingsInWeekView = UserDefaults.standard.object(forKey: Keys.showClassMeetingsInWeekView) as? Bool ?? false
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
        notificationsEnabled = false
        showClassMeetingsInWeekView = false
    }
}
