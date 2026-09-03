//
//  ClassAutoResync.swift
//  Plannr
//
//  Fire-and-forget re-sync of a class's pending changes. Used when the network
//  comes back (or the app returns to the foreground) so a sync that failed all
//  its retries earlier isn't stuck waiting for the user to tap "Re-sync". No UI,
//  silent on failure — the class simply keeps `hasUnsyncedChanges` for a later
//  manual attempt.
//

import Foundation

enum ClassAutoResync {

    /// Push `cls`'s incremental changes. Returns the updated class on success
    /// (HTTP 200), or `nil` when there was nothing to send, the request couldn't
    /// be built, or the sync failed — in which case the caller leaves the class
    /// untouched.
    static func run(
        _ cls: Class,
        reminderMinutes: Int?,
        send: (URLRequest) async throws -> (Data, HTTPURLResponse)
    ) async -> Class? {
        // Nothing to do for a class that never synced, a guest/sample class, or
        // one with no pending edits.
        guard cls.googleCalendarId != nil, !cls.isSample else { return nil }
        let events = ClassSyncRequest.incrementalEvents(from: cls.events)
        guard !events.isEmpty else { return nil }

        guard let request = try? ClassSyncRequest.makeRequest(
            email: UserDefaults.standard.string(forKey: "userEmail"),
            className: cls.name,
            googleCalendarId: cls.googleCalendarId,
            classColorHex: cls.colorHex,
            reminderMinutes: reminderMinutes,
            events: events
        ) else { return nil }

        guard let (data, http) = try? await send(request),
              http.statusCode == 200,
              let response = try? JSONDecoder().decode(ClassSyncRequest.Response.self, from: data)
        else { return nil }

        return ClassSyncRequest.apply(response, to: cls)
    }
}
