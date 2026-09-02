//
//  ClassEditView.swift
//  Plannr
//

import SwiftUI


// MARK: - Sync response models

private struct ClassSyncResponse: Decodable {
    let googleCalendarId: String
    let syncedEvents: [SyncedEventEntry]

    private enum CodingKeys: String, CodingKey {
        case googleCalendarId = "google_calendar_id"
        case syncedEvents = "synced_events"
    }
}

private struct SyncedEventEntry: Decodable {
    let localId: String
    let googleEventId: String

    private enum CodingKeys: String, CodingKey {
        case localId = "local_id"
        case googleEventId = "google_event_id"
    }
}

// MARK: - ClassEditView

struct ClassEditView: View {
    @EnvironmentObject var classManager: ClassManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    // Local mutable copy of the class
    @State private var editableClass: Class
    @State private var editingEvent: CalendarEvent?
    @State private var isSyncing = false
    @State private var syncErrorMessage: String?
    @State private var showSyncError = false
    @State private var showSyncSuccess = false
    @State private var navigateToUpload = false
    @State private var showEndDatePicker = false
    @State private var showSyncSessions = false
    @State private var scheduleDraft: ClassSchedule
    @State private var showScheduleEditor = false
    @State private var isSyncingMeetings = false
    @State private var meetingSyncError: String?
    @State private var showMeetingSyncError = false

    var onSyncComplete: (() -> Void)?

    init(cls: Class, onSyncComplete: (() -> Void)? = nil) {
        _editableClass = State(initialValue: cls)
        _scheduleDraft = State(initialValue: cls.structuredSchedule ?? ClassSchedule())
        self.onSyncComplete = onSyncComplete
    }

    // All events shown in the list; soft-deleted ones are visually marked but kept until resync
    private var visibleEvents: [CalendarEvent] {
        editableClass.events
    }

    private var activeEventCount: Int {
        editableClass.events.filter { !$0.isDeletedLocally }.count
    }

    // Count of changes pending a re-sync
    private var unsyncedCount: Int {
        editableClass.events.filter { $0.isEdited || $0.isDeletedLocally }.count
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // ── Header ────────────────────────────────────────
                        classHeader

                        // ── Weekly schedule + class-meeting sync ──────────
                        scheduleSection

                        // ── Events list ───────────────────────────────────
                        eventsSection
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 100) // leave room for the sticky button
                }

                // ── Sticky bottom button ───────────────────────────────
                bottomButton
            }
        }
        .navigationTitle(editableClass.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingEvent) { event in
            EventEditView(event: event) { updatedEvent in
                applyEventEdit(updatedEvent)
                editingEvent = nil
            }
        }
        .navigationDestination(isPresented: $showSyncSessions) {
            SyncSessionsView(sessions: editableClass.syncHistory)
        }
        .navigationDestination(isPresented: $navigateToUpload) {
            SyllabusUploadView(
                className: editableClass.name,
                classSchedule: editableClass.schedule,
                classColor: editableClass.color,
                existingClassID: editableClass.id,
                existingEvents: editableClass.events,
                onSyncComplete: {
                    // Reload class from classManager to pick up new events + status
                    if let updated = classManager.classes.first(where: { $0.id == editableClass.id }) {
                        editableClass = updated
                        // Adopt a schedule the parser auto-filled, but never stomp
                        // a schedule the user was already editing.
                        if scheduleDraft.isEmpty, let parsed = updated.structuredSchedule {
                            scheduleDraft = parsed
                        }
                    }
                    // Pop SyllabusUploadView + CalendarPreviewView back to ClassEditView
                    navigateToUpload = false
                }
            )
            .environmentObject(classManager)
            .environmentObject(authManager)
            .environmentObject(settingsManager)
        }
        .alert("Sync Failed", isPresented: $showSyncError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(syncErrorMessage ?? "An unknown error occurred.")
        }
        .alert(authManager.isGuest ? "Changes Saved" : "Sync Successful", isPresented: $showSyncSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authManager.isGuest ? "Your changes have been saved." : "Your changes have been synced to Google Calendar.")
        }
        .onAppear {
            // Refresh from classManager in case another view updated it
            if let latest = classManager.classes.first(where: { $0.id == editableClass.id }) {
                editableClass = latest
            }
            // Auto-transition to inactive if end date has passed
            if let endDate = editableClass.endDate, Date() > endDate, editableClass.status == .active {
                goInactive()
            }
        }
    }

    // MARK: - Header

    private var classHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(editableClass.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                // Status picker (ACTIVE / INACTIVE only; NO_SYLLABUS is read-only)
                if editableClass.status == .noSyllabus {
                    Text("NO SYLLABUS")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(8)
                } else {
                    Menu {
                        Button("ACTIVE") { goActive() }
                        Button("INACTIVE") { goInactive() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(editableClass.status == .active ? "ACTIVE" : "INACTIVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundColor(editableClass.status == .active ? editableClass.color : .gray)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            (editableClass.status == .active ? editableClass.color : Color.gray).opacity(0.2)
                        )
                        .cornerRadius(8)
                    }
                }
            }

            // Color picker (no label — circle swatch speaks for itself)
            ColorPicker(selection: Binding(
                get: { editableClass.color },
                set: { newColor in
                    editableClass.colorHex = newColor.toHex()
                    persistClass()
                    // Sync color to Google Calendar immediately if class has been synced before
                    if !authManager.isGuest && editableClass.googleCalendarId != nil {
                        Task { await syncColorChange() }
                    }
                }
            ), supportsOpacity: false) {
                EmptyView()
            }
            .frame(maxWidth: 40) // constrain to just the swatch

            // End date row
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("End date")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    if let endDate = editableClass.endDate {
                        Text(endDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.white)
                        Button {
                            editableClass.endDate = nil
                            persistClass()
                            showEndDatePicker = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    } else {
                        Button("Set") {
                            showEndDatePicker.toggle()
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                if showEndDatePicker {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { editableClass.endDate ?? Calendar.current.date(byAdding: .month, value: 3, to: Date())! },
                            set: { newDate in
                                editableClass.endDate = newDate
                                persistClass()
                                showEndDatePicker = false
                            }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .colorScheme(.dark)
                    .labelsHidden()
                }
            }

            // Last synced
            if let lastSynced = editableClass.lastSynced {
                Text("Last synced: \(lastSynced.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Schedule + class meetings

    private var scheduleHasContent: Bool { !(editableClass.structuredSchedule?.isEmpty ?? true) }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(editableClass.schedule.isEmpty ? "No schedule set" : editableClass.schedule)
                    .font(.caption)
                    .foregroundColor(editableClass.schedule.isEmpty ? .gray : .white)
                Spacer()
                Button("Edit") { showScheduleEditor = true }
                    .font(.caption)
                    .foregroundColor(.blue)
            }

            if !authManager.isGuest {
                Toggle(isOn: Binding(
                    get: { editableClass.meetingSyncEnabled },
                    set: { newValue in
                        editableClass.meetingSyncEnabled = newValue
                        persistClass()
                        Task { await syncClassMeetings() }
                    }
                )) {
                    HStack(spacing: 6) {
                        if isSyncingMeetings {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text("Add class meetings to Google Calendar")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                }
                .tint(.blue)
                .disabled(isSyncingMeetings || !scheduleHasContent)

                Text(scheduleHasContent
                     ? "Adds your weekly lecture/section times to this class's calendar as recurring events. They don't show in Week at a Glance or Calendar views unless enabled in Settings."
                     : "Set a schedule above first.")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .cornerRadius(12)
        .padding(.horizontal)
        .onChange(of: scheduleDraft) { _, newValue in
            editableClass.structuredSchedule = newValue.isEmpty ? nil : newValue
            editableClass.schedule = newValue.displayString
            persistClass()
            if editableClass.meetingSyncEnabled && !authManager.isGuest {
                Task { await syncClassMeetings(isToggleAction: false) }
            }
        }
        .sheet(isPresented: $showScheduleEditor) {
            scheduleEditorSheet
        }
        .alert("Class Meetings", isPresented: $showMeetingSyncError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(meetingSyncError ?? "Something went wrong. Please try again.")
        }
    }

    private var scheduleEditorSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    ClassSchedulePicker(schedule: $scheduleDraft)
                        .padding()
                }
            }
            .navigationTitle("Class Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showScheduleEditor = false }
                        .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Events section

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Events (\(activeEventCount))")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                if !editableClass.syncHistory.isEmpty {
                    Button {
                        showSyncSessions = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption)
                            Text("View Sync Sessions")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal)

            if visibleEvents.isEmpty {
                Text("No events yet. Upload a PDF to get started.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
            } else {
                ForEach(visibleEvents) { event in
                    ClassEventRow(event: event, classColor: editableClass.color) {
                        editingEvent = event
                    } onDelete: {
                        toggleDeleteEvent(event)
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Bottom button

    private var bottomButton: some View {
        Group {
            if authManager.isGuest && editableClass.hasUnsyncedChanges {
                Button(action: { saveLocally() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Changes")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color.black)
            } else if !authManager.isGuest && editableClass.hasUnsyncedChanges {
                Button(action: { Task { await resyncChanges() } }) {
                    HStack(spacing: 8) {
                        if isSyncing {
                            ProgressView().tint(.white)
                        }
                        Text(isSyncing ? "Syncing..." : "Re-sync (\(unsyncedCount)) \(unsyncedCount == 1 ? "Change" : "Changes")")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isSyncing ? Color.gray : Color.blue)
                    .cornerRadius(12)
                }
                .disabled(isSyncing)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color.black)
            } else {
                Button(action: { navigateToUpload = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc.fill")
                        Text("Upload New Syllabus")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color.black)
            }
        }
    }

    // MARK: - Helpers

    private func applyEventEdit(_ updated: CalendarEvent) {
        guard let idx = editableClass.events.firstIndex(where: { $0.id == updated.id }) else { return }
        var mutated = updated
        mutated.isEdited = true
        editableClass.events[idx] = mutated
        editableClass.hasUnsyncedChanges = true
        persistClass()
        autoSyncIfEnabled()
    }

    private func toggleDeleteEvent(_ event: CalendarEvent) {
        guard let idx = editableClass.events.firstIndex(where: { $0.id == event.id }) else { return }
        editableClass.events[idx].isDeletedLocally.toggle()
        editableClass.hasUnsyncedChanges = editableClass.events.contains { $0.isEdited || $0.isDeletedLocally }
        persistClass()
        autoSyncIfEnabled()
    }

    /// If auto-sync is on (and the class has synced before), push changes immediately
    /// instead of waiting for a manual "Re-sync" tap.
    private func autoSyncIfEnabled() {
        guard settingsManager.autoSyncEnabled, !authManager.isGuest, !isSyncing,
              editableClass.googleCalendarId != nil else { return }
        Task { await resyncChanges() }
    }
    
    private func persistClass() {
        classManager.updateClass(editableClass)
    }

    // MARK: - Active / inactive transitions

    private func goActive() {
        editableClass.status = .active
        persistClass()
        // Re-check the class's calendar in Google Calendar's sidebar.
        if !authManager.isGuest && editableClass.googleCalendarId != nil {
            Task { await setCalendarVisibility(selected: true) }
        }
    }

    /// Marking a class done: drop its recurring meetings from Google Calendar and
    /// uncheck (hide) its calendar there, without deleting the calendar itself.
    private func goInactive() {
        editableClass.status = .inactive
        let hadMeetingSync = editableClass.meetingSyncEnabled
        if hadMeetingSync { editableClass.meetingSyncEnabled = false }
        persistClass()
        guard !authManager.isGuest else { return }
        Task {
            if hadMeetingSync { await syncClassMeetings(isToggleAction: false) }
            await setCalendarVisibility(selected: false)
        }
    }

    // MARK: - Guest local save (no Google Calendar)

    private func saveLocally() {
        // Remove events the user queued for deletion
        editableClass.events.removeAll { $0.isDeletedLocally }
        // Clear edit flags
        for i in editableClass.events.indices {
            editableClass.events[i].isEdited = false
        }
        editableClass.hasUnsyncedChanges = false
        if editableClass.status == .noSyllabus && !editableClass.events.isEmpty {
            editableClass.status = .active
        }
        persistClass()
        showSyncSuccess = true
    }

    // MARK: - Re-sync

    private func syncColorChange() async {
        guard let email = UserDefaults.standard.string(forKey: "userEmail"),
              let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(BACKEND_URL)calendar/sync?email=\(encodedEmail)") else {
            return
        }

        // Reuse existing SyncEventBody and SyncRequestBody structs for consistency
        struct SyncEventBody: Encodable {
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
        }

        struct ColorSyncBody: Encodable {
            let className: String
            let googleCalendarId: String?
            let events: [SyncEventBody] // Empty array for color-only sync
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

        let body = ColorSyncBody(
            className: editableClass.name,
            googleCalendarId: editableClass.googleCalendarId,
            events: [], // No event changes, just color
            backgroundColor: editableClass.colorHex.hasPrefix("#") ? editableClass.colorHex : "#\(editableClass.colorHex)",
            foregroundColor: "#FFFFFF",
            reminderMinutes: settingsManager.reminderMinutes
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(body)
            // Routed through `send` so a revoked token still triggers sign-out,
            // even though the color sync itself reports nothing to the user.
            _ = try await authManager.send(request)
        } catch {
            // Silent failure for color sync
        }
    }

    /// Check/uncheck this class's calendar in the user's Google Calendar sidebar.
    /// Called when the class is switched active/inactive. Best-effort and silent:
    /// a class with no synced calendar yet has nothing to toggle.
    private func setCalendarVisibility(selected: Bool) async {
        guard !authManager.isGuest,
              let calId = editableClass.googleCalendarId,
              let email = UserDefaults.standard.string(forKey: "userEmail"),
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
        request.timeoutInterval = 90
        do {
            request.httpBody = try JSONEncoder().encode(VisibilityBody(googleCalendarId: calId, selected: selected))
            _ = try await authManager.send(request)
        } catch {
            // Silent — visibility is a convenience, not a correctness requirement.
        }
    }

    // MARK: - Class meeting sync

    private func syncClassMeetings(isToggleAction: Bool = true) async {
        guard !authManager.isGuest,
              let email = UserDefaults.standard.string(forKey: "userEmail"),
              let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(BACKEND_URL)calendar/meetings?email=\(encodedEmail)") else { return }

        let enabled = editableClass.meetingSyncEnabled
        let schedule = editableClass.structuredSchedule

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
                                  ?? settingsManager.term.startDate ?? Date())
        // "Repeat for X weeks" wins; otherwise fall back to the class/term end.
        let weekCount = enabled ? schedule?.weekCount : nil
        let untilDate = (editableClass.endDate ?? settingsManager.term.endDate).map { df.string(from: $0) }

        let finalExam: FinalExamBody? = (enabled ? schedule?.finalExam : nil).map { fe in
            FinalExamBody(date: df.string(from: fe.date),
                          start_time: fe.start.iso,
                          duration_minutes: fe.durationMinutes)
        }

        let requestBody = MeetingsRequestBody(
            class_name: editableClass.name,
            google_calendar_id: editableClass.googleCalendarId,
            background_color: editableClass.colorHex.hasPrefix("#") ? editableClass.colorHex : "#\(editableClass.colorHex)",
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
            await MainActor.run {
                meetingSyncError = "Couldn't build the request. Please try again."
                showMeetingSyncError = true
            }
            return
        }

        await MainActor.run { isSyncingMeetings = true }

        do {
            let (data, http) = try await authManager.send(request)
            await MainActor.run {
                isSyncingMeetings = false
                if http.statusCode == 401 { return }
                if http.statusCode == 200,
                   let resp = try? JSONDecoder().decode(MeetingsResponse.self, from: data) {
                    if let calId = resp.googleCalendarId { editableClass.googleCalendarId = calId }
                    editableClass.meetingEventIds = resp.meetings.map(\.googleEventId)
                    persistClass()
                } else {
                    let bodyText = String(data: data, encoding: .utf8) ?? ""
                    let parsed = (try? JSONDecoder().decode([String: String].self, from: data))
                    let msg = parsed?["error"] ?? parsed?["detail"]
                    print("Class meeting sync failed [\(http.statusCode)]: \(bodyText.prefix(500))")
                    meetingSyncError = msg
                        ?? "Couldn't update class meetings (server said \(http.statusCode)). Please try again."
                    showMeetingSyncError = true
                    // Only revert the toggle for a definite client error; leave it
                    // as-is on a 5xx / cold start so a retry doesn't need re-toggling.
                    if isToggleAction && (400..<500).contains(http.statusCode) {
                        editableClass.meetingSyncEnabled = !enabled
                        persistClass()
                    }
                }
            }
        } catch {
            await MainActor.run {
                isSyncingMeetings = false
                meetingSyncError = "Network error: \(error.localizedDescription)"
                showMeetingSyncError = true
            }
        }
    }

    private func resyncChanges() async {
        guard let email = UserDefaults.standard.string(forKey: "userEmail"),
              let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(BACKEND_URL)calendar/sync?email=\(encodedEmail)") else {
            syncErrorMessage = "Could not determine your account email."
            showSyncError = true
            return
        }

        await MainActor.run { isSyncing = true }

        // Build request body
        struct SyncEventBody: Encodable {
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
        }

        struct SyncRequestBody: Encodable {
            let className: String
            let googleCalendarId: String?
            let events: [SyncEventBody]
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

        // Only send events that actually need action:
        //   - New events (no Google ID, not deleted) → insert
        //   - Edited events with a Google ID → update
        //   - Locally-deleted events with a Google ID → delete in GCal
        // Unchanged, already-synced events are intentionally skipped.
        let eventsToSync: [SyncEventBody] = editableClass.events.compactMap { ev in
            let needsInsert  = ev.googleEventId == nil && !ev.isDeletedLocally
            let needsUpdate  = ev.isEdited && ev.googleEventId != nil
            let needsDelete  = ev.isDeletedLocally && ev.googleEventId != nil
            guard needsInsert || needsUpdate || needsDelete else { return nil }
            return SyncEventBody(
                localId: ev.id.uuidString,
                title: ev.title,
                date: ev.date,
                description: ev.description,
                type: ev.type,
                googleEventId: ev.googleEventId,
                isDeleted: ev.isDeletedLocally
            )
        }

        let body = SyncRequestBody(
            className: editableClass.name,
            googleCalendarId: editableClass.googleCalendarId,
            events: eventsToSync,
            backgroundColor: editableClass.colorHex.hasPrefix("#") ? editableClass.colorHex : "#\(editableClass.colorHex)",
            foregroundColor: "#FFFFFF",  // White text for better contrast
            reminderMinutes: settingsManager.reminderMinutes
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            await MainActor.run {
                isSyncing = false
                syncErrorMessage = "Failed to encode sync request."
                showSyncError = true
            }
            return
        }

        do {
            let (data, http) = try await authManager.send(request)
            await MainActor.run {
                isSyncing = false
                if http.statusCode == 401 { return }  // session-expired sign-out already triggered
                if http.statusCode == 200,
                   let syncResponse = try? JSONDecoder().decode(ClassSyncResponse.self, from: data) {
                    applySync(response: syncResponse)
                } else if let errBody = try? JSONDecoder().decode([String: String].self, from: data),
                          let errMsg = errBody["error"] {
                    syncErrorMessage = errMsg
                    showSyncError = true
                } else {
                    syncErrorMessage = "Re-sync failed. Please try again."
                    showSyncError = true
                }
            }
        } catch {
            await MainActor.run {
                isSyncing = false
                syncErrorMessage = "Network error: \(error.localizedDescription)"
                showSyncError = true
            }
        }
    }

    private func applySync(response: ClassSyncResponse) {
        // Update calendar ID
        editableClass.googleCalendarId = response.googleCalendarId

        // Build lookup: localId → googleEventId
        let idMap = Dictionary(uniqueKeysWithValues: response.syncedEvents.map { ($0.localId, $0.googleEventId) })

        // Apply to events
        for i in editableClass.events.indices {
            let ev = editableClass.events[i]
            if ev.isDeletedLocally {
                // Will be removed below
                continue
            }
            if let gid = idMap[ev.id.uuidString] {
                editableClass.events[i].googleEventId = gid
            }
            editableClass.events[i].isEdited = false
        }

        // Remove soft-deleted events from local storage
        editableClass.events.removeAll { $0.isDeletedLocally }

        // Update class metadata
        editableClass.hasUnsyncedChanges = false
        editableClass.lastSynced = Date()
        if editableClass.status == .noSyllabus {
            editableClass.status = .active
        }
        
        editableClass.syncHistory.append(SyncSession(events: editableClass.events))

        persistClass()
        showSyncSuccess = true
    }
}

// MARK: - ClassEventRow

struct ClassEventRow: View {
    let event: CalendarEvent
    let classColor: Color
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(event.isDeletedLocally ? Color.red : classColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(event.isDeletedLocally ? .gray : .white)
                        .strikethrough(event.isDeletedLocally, color: .gray)

                    Spacer()

                    if event.isDeletedLocally {
                        Text("QUEUED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.2))
                            .cornerRadius(6)
                    } else if event.isEdited {
                        Text("EDITED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.yellow.opacity(0.2))
                            .cornerRadius(6)
                    }

                    Text(event.type.capitalized)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(classColor.opacity(0.3))
                        .cornerRadius(6)
                }

                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(event.date)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                if !event.description.isEmpty {
                    Text(event.description)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil").font(.caption2)
                            Text("Edit").font(.caption2).fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(event.isDeletedLocally ? 0.2 : 0.6))
                        .cornerRadius(6)
                    }
                    .disabled(event.isDeletedLocally)

                    Button(action: onDelete) {
                        HStack(spacing: 4) {
                            Image(systemName: event.isDeletedLocally ? "arrow.uturn.backward" : "trash")
                                .font(.caption2)
                            Text(event.isDeletedLocally ? "Undo" : "Delete")
                                .font(.caption2).fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(event.isDeletedLocally ? Color.red : Color.red.opacity(0.6))
                        .cornerRadius(6)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding()
        .background(event.isDeletedLocally ? Color.red.opacity(0.08) : Color.gray.opacity(0.12))
        .cornerRadius(10)
    }
}

#Preview {
    NavigationStack {
        ClassEditView(cls: Class(
            name: "CS148",
            schedule: "MWF 10:00 AM",
            colorHex: "007AFF",
            events: [
                CalendarEvent(title: "HW1", date: "2026-03-15", type: "homework", description: "Chapter 1"),
                CalendarEvent(title: "Midterm 1", date: "2026-03-20", type: "exam", description: "Covers weeks 1-4")
            ],
            status: .active
        ))
        .environmentObject(ClassManager())
        .environmentObject(AuthManager())
        .environmentObject(SettingsManager.shared)
    }
}
