//
//  ClassMeetingSync.swift
//  Plannr
//
//  Builds and runs the POST /calendar/meetings request for one class. Shared by
//  ClassEditView (the per-class toggle, with an error alert) and the
//  "auto-sync class meetings" path that fires when a scheduled class is created.
//

import Foundation

enum ClassMeetingSync {

    enum Outcome {
        /// 200 — the class with `googleCalendarId` / `meetingEventIds` updated.
        case updated(Class)
        /// 401 — session expired; the shared `send` already started sign-out.
        case unauthorized
        /// Non-2xx or a transport failure. `clientError` marks a 4xx that a retry
        /// won't fix (so the caller can revert an optimistic toggle).
        case failed(message: String, clientError: Bool)
    }

    /// - Parameters:
    ///   - cls: the class to sync. `cls.meetingSyncEnabled` decides whether the
    ///          backend writes the meetings (true) or clears them (false).
    ///   - send: pass `authManager.send` so a revoked token still triggers sign-out.
    static func run(
        for cls: Class,
        settings: SettingsManager,
        send: (URLRequest) async throws -> (Data, HTTPURLResponse)
    ) async -> Outcome {
        guard let email = UserDefaults.standard.string(forKey: "userEmail"),
              let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(BACKEND_URL)calendar/meetings?email=\(encodedEmail)") else {
            return .failed(message: "Could not determine your account email.", clientError: true)
        }

        let enabled = cls.meetingSyncEnabled
        let schedule = cls.structuredSchedule

        struct PatternBody: Encodable {
            let kind: String
            let byday: [String]
            let start_time: String
            let duration_minutes: Int
        }
        struct FinalExamBody: Encodable {
            let date: String
            let start_time: String
            let duration_minutes: Int
        }
        struct MeetingsRequestBody: Encodable {
            let class_name: String
            let google_calendar_id: String?
            let background_color: String?
            let foreground_color: String?
            let timezone: String
            let start_date: String
            let until_date: String?
            let week_count: Int?
            let patterns: [PatternBody]
            let final_exam: FinalExamBody?
        }
        struct MeetingsResponse: Decodable {
            struct Meeting: Decodable {
                let kind: String
                let googleEventId: String
                enum CodingKeys: String, CodingKey { case kind; case googleEventId = "google_event_id" }
            }
            let googleCalendarId: String?
            let meetings: [Meeting]
            enum CodingKeys: String, CodingKey {
                case googleCalendarId = "google_calendar_id"
                case meetings
            }
        }

        // Declarative: the backend replaces its tagged meeting events with exactly
        // these patterns (empty = remove them all). No id bookkeeping needed here.
        let patterns: [PatternBody] = (enabled ? (schedule?.patterns ?? []) : []).map { pattern in
            PatternBody(
                kind: pattern.kind.rawValue,
                byday: pattern.days.compactMap { Weekday(rawValue: $0)?.byday },
                start_time: pattern.start.iso,
                duration_minutes: pattern.durationMinutes
            )
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = Calendar(identifier: .gregorian)
        df.dateFormat = "yyyy-MM-dd"

        // First meeting: the schedule's own date, else the term start, else today.
        let startDate = df.string(from: schedule?.firstMeetingDate
                                  ?? settings.term.startDate ?? Date())
        // "Repeat for X weeks" wins; otherwise fall back to the class/term end.
        let weekCount = enabled ? schedule?.weekCount : nil
        let untilDate = (cls.endDate ?? settings.term.endDate).map { df.string(from: $0) }

        let finalExam: FinalExamBody? = (enabled ? schedule?.finalExam : nil).map { fe in
            FinalExamBody(date: df.string(from: fe.date),
                          start_time: fe.start.iso,
                          duration_minutes: fe.durationMinutes)
        }

        let requestBody = MeetingsRequestBody(
            class_name: cls.name,
            google_calendar_id: cls.googleCalendarId,
            background_color: cls.colorHex.hasPrefix("#") ? cls.colorHex : "#\(cls.colorHex)",
            foreground_color: "#FFFFFF",
            timezone: TimeZone.current.identifier,
            start_date: startDate,
            until_date: untilDate,
            week_count: weekCount,
            patterns: patterns,
            final_exam: finalExam
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The class calendar may not exist yet, and the backend runs several
        // Google Calendar calls — allow for a cold start on Render's free tier.
        request.timeoutInterval = 90
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            return .failed(message: "Couldn't build the request. Please try again.", clientError: true)
        }

        do {
            let (data, http) = try await send(request)
            if http.statusCode == 401 { return .unauthorized }
            if http.statusCode == 200,
               let resp = try? JSONDecoder().decode(MeetingsResponse.self, from: data) {
                var updated = cls
                if let calId = resp.googleCalendarId { updated.googleCalendarId = calId }
                updated.meetingEventIds = resp.meetings.map(\.googleEventId)
                return .updated(updated)
            }
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            let parsed = try? JSONDecoder().decode([String: String].self, from: data)
            let msg = parsed?["error"] ?? parsed?["detail"]
                ?? "Couldn't update class meetings (server said \(http.statusCode)). Please try again."
            print("Class meeting sync failed [\(http.statusCode)]: \(bodyText.prefix(500))")
            return .failed(message: msg, clientError: (400..<500).contains(http.statusCode))
        } catch {
            return .failed(message: "Network error: \(error.localizedDescription)", clientError: false)
        }
    }
}
