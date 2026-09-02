//
//  NotificationManager.swift
//  Plannr
//
//  Schedules local reminder notifications for upcoming class deadlines.
//

import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    /// iOS keeps at most 64 pending local notifications per app and silently
    /// drops the rest. Cap our reminders below that (leaving a little headroom)
    /// and only schedule the *soonest* ones — `sync()` runs on every foreground,
    /// so the window rolls forward as earlier reminders fire.
    static let maxScheduledReminders = 60

    /// One planned reminder — the pure output of `plannedReminders`, before it
    /// touches `UNUserNotificationCenter`.
    struct PlannedReminder: Equatable {
        let identifier: String
        let title: String
        let body: String
        let fireDate: Date
        let fireComponents: DateComponents
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func checkAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            }
        }
    }

    /// Cancel all scheduled deadline reminders, then reschedule the nearest
    /// `maxScheduledReminders` from current classes/settings.
    func sync(classes: [Class], notificationsEnabled: Bool, leadDays: Int) {
        cancelAll()
        guard notificationsEnabled else { return }

        for reminder in Self.plannedReminders(for: classes, leadDays: leadDays) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: reminder.fireComponents, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// The future deadline reminders across all classes, soonest-first, capped at
    /// `limit`. Pure — no side effects — so it can be unit-tested.
    static func plannedReminders(
        for classes: [Class],
        leadDays: Int,
        now: Date = Date(),
        calendar: Calendar = .current,
        limit: Int = maxScheduledReminders
    ) -> [PlannedReminder] {
        guard leadDays >= 0, limit > 0 else { return [] }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.calendar = calendar
        df.timeZone = calendar.timeZone
        df.locale = Locale(identifier: "en_US_POSIX")

        var planned: [PlannedReminder] = []
        for cls in classes {
            for event in cls.events where !event.isDeletedLocally {
                guard let dueDate = df.date(from: event.date),
                      let leadAdjusted = calendar.date(byAdding: .day, value: -leadDays, to: dueDate) else { continue }

                var components = calendar.dateComponents([.year, .month, .day], from: leadAdjusted)
                components.hour = 9
                guard let fireDate = calendar.date(from: components), fireDate > now else { continue }

                let body = leadDays == 0
                    ? "\(event.title) is due today"
                    : "\(event.title) is due in \(leadDays) day\(leadDays == 1 ? "" : "s")"

                planned.append(PlannedReminder(
                    identifier: event.id.uuidString,
                    title: cls.name,
                    body: body,
                    fireDate: fireDate,
                    fireComponents: components
                ))
            }
        }

        return Array(planned.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }
}
