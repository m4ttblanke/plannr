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

    /// Cancel all scheduled deadline reminders, then reschedule from scratch based on current classes/settings.
    func sync(classes: [Class], notificationsEnabled: Bool, leadDays: Int) {
        cancelAll()
        guard notificationsEnabled, leadDays >= 0 else { return }
        for cls in classes {
            for event in cls.events where !event.isDeletedLocally {
                schedule(event: event, className: cls.name, leadDays: leadDays)
            }
        }
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private func schedule(event: CalendarEvent, className: String, leadDays: Int) {
        guard let dueDate = Self.dateFormatter.date(from: event.date),
              let fireDate = Calendar.current.date(byAdding: .day, value: -leadDays, to: dueDate),
              fireDate > Date() else { return }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
        components.hour = 9

        let content = UNMutableNotificationContent()
        content.title = className
        content.body = leadDays == 0
            ? "\(event.title) is due today"
            : "\(event.title) is due in \(leadDays) day\(leadDays == 1 ? "" : "s")"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}
