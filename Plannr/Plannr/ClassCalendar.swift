//
//  ClassCalendar.swift
//  Plannr
//
//  Small Google-Calendar side effects shared by ClassEditView's active/inactive
//  transitions and the "Archive term" bulk action.
//

import Foundation

enum ClassCalendar {

    /// Check / uncheck a class's dedicated calendar in the Google Calendar
    /// sidebar. Best-effort and silent — a class with no synced calendar has
    /// nothing to toggle.
    static func setVisibility(
        calendarId: String,
        selected: Bool,
        send: (URLRequest) async throws -> (Data, HTTPURLResponse)
    ) async {
        guard let email = UserDefaults.standard.string(forKey: "userEmail"),
              let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(BACKEND_URL)calendar/visibility?email=\(encodedEmail)") else { return }

        struct VisibilityBody: Encodable {
            let googleCalendarId: String
            let selected: Bool
            enum CodingKeys: String, CodingKey {
                case googleCalendarId = "google_calendar_id"
                case selected
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        attachBackendAuth(&request)
        request.timeoutInterval = 90
        do {
            request.httpBody = try JSONEncoder().encode(VisibilityBody(googleCalendarId: calendarId, selected: selected))
            _ = try await send(request)
        } catch {
            // Silent — visibility is a convenience, not a correctness requirement.
        }
    }
}
