//
//  ClassSyncRequest.swift
//  Plannr
//
//  Builds the POST /calendar/sync request and models its response. Shared by
//  CalendarPreviewView (a full accept/decline sync), ClassEditView (an
//  incremental re-sync), and ClassEditView's colour-only sync — each of which
//  used to redefine the same nested request/response structs inline.
//

import Foundation

enum ClassSyncRequest {

    /// One event in the sync payload. `is_deleted` events must carry a
    /// `google_event_id` for the backend to remove them.
    struct EventBody: Encodable, Equatable {
        let localId: String
        let title: String
        let date: String
        let description: String
        let type: String
        let googleEventId: String?
        let isDeleted: Bool

        enum CodingKeys: String, CodingKey {
            case localId = "local_id"
            case title, date, description, type
            case googleEventId = "google_event_id"
            case isDeleted = "is_deleted"
        }

        init(_ event: CalendarEvent, isDeleted: Bool) {
            localId = event.id.uuidString
            title = event.title
            date = event.date
            description = event.description
            type = event.type
            googleEventId = event.googleEventId
            self.isDeleted = isDeleted
        }
    }

    struct Response: Decodable {
        let googleCalendarId: String
        let syncedEvents: [Synced]

        struct Synced: Decodable {
            let localId: String
            let googleEventId: String
            enum CodingKeys: String, CodingKey {
                case localId = "local_id"
                case googleEventId = "google_event_id"
            }
        }

        enum CodingKeys: String, CodingKey {
            case googleCalendarId = "google_calendar_id"
            case syncedEvents = "synced_events"
        }
    }

    /// A full sync: every accepted event (with its Google id, or nil so the
    /// backend inserts it) plus the reconciled deletions.
    static func fullSyncEvents(accepted: [CalendarEvent], deletions: [CalendarEvent]) -> [EventBody] {
        accepted.map { EventBody($0, isDeleted: false) }
            + deletions.map { EventBody($0, isDeleted: true) }
    }

    /// An incremental re-sync: only events that need an insert (new, no id),
    /// an update (edited, has id) or a delete (locally-deleted, has id).
    /// Unchanged, already-synced events are skipped.
    static func incrementalEvents(from events: [CalendarEvent]) -> [EventBody] {
        events.compactMap { ev in
            let needsInsert = ev.googleEventId == nil && !ev.isDeletedLocally
            let needsUpdate = ev.isEdited && ev.googleEventId != nil
            let needsDelete = ev.isDeletedLocally && ev.googleEventId != nil
            guard needsInsert || needsUpdate || needsDelete else { return nil }
            return EventBody(ev, isDeleted: ev.isDeletedLocally)
        }
    }

    /// Normalize a stored hex ("AF52DE" or "#AF52DE") to "#AF52DE".
    static func hashHex(_ hex: String) -> String {
        hex.hasPrefix("#") ? hex : "#\(hex)"
    }

    /// Fold a successful `/calendar/sync` response back into a class: record the
    /// new Google event ids, clear the `isEdited` flags, drop the
    /// locally-deleted events, and mark the class synced. Pure — the caller
    /// persists the result. Shared by the interactive re-sync and the
    /// reconnect auto-resync.
    static func apply(_ response: Response, to cls: Class, now: Date = Date()) -> Class {
        var updated = cls
        updated.googleCalendarId = response.googleCalendarId

        let idMap = Dictionary(response.syncedEvents.map { ($0.localId, $0.googleEventId) },
                               uniquingKeysWith: { _, new in new })
        for i in updated.events.indices where !updated.events[i].isDeletedLocally {
            if let gid = idMap[updated.events[i].id.uuidString] {
                updated.events[i].googleEventId = gid
            }
            updated.events[i].isEdited = false
        }
        updated.events.removeAll { $0.isDeletedLocally }

        updated.hasUnsyncedChanges = false
        updated.lastSynced = now
        if updated.status == .noSyllabus {
            updated.status = .active
        }
        updated.syncHistory.append(SyncSession(events: updated.events))
        return updated
    }

    private struct Body: Encodable {
        let className: String
        let googleCalendarId: String?
        let events: [EventBody]
        let backgroundColor: String?
        let foregroundColor: String?
        let reminderMinutes: Int?

        enum CodingKeys: String, CodingKey {
            case className = "class_name"
            case googleCalendarId = "google_calendar_id"
            case events
            case backgroundColor = "background_color"
            case foregroundColor = "foreground_color"
            case reminderMinutes = "reminder_minutes"
        }
    }

    /// Build the request, or `nil` if the account email can't be resolved into a
    /// URL. Throws only if JSON encoding fails.
    static func makeRequest(
        email: String?,
        className: String,
        googleCalendarId: String?,
        classColorHex: String,
        reminderMinutes: Int?,
        events: [EventBody]
    ) throws -> URLRequest? {
        guard let email,
              let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(BACKEND_URL)calendar/sync?email=\(encodedEmail)") else {
            return nil
        }

        let body = Body(
            className: className,
            googleCalendarId: googleCalendarId,
            events: events,
            backgroundColor: hashHex(classColorHex),
            foregroundColor: "#FFFFFF",
            reminderMinutes: reminderMinutes
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}
