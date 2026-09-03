//
//  ClassEditView.swift
//  Plannr
//

import SwiftUI

// MARK: - ClassEditView

struct ClassEditView: View {
    @EnvironmentObject var classManager: ClassManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var termStore: TermStore
    @EnvironmentObject var sampleTour: SampleTour
    @Environment(\.dismiss) private var dismiss

    // Local mutable copy of the class
    @State private var editableClass: Class
    @State private var editingEvent: CalendarEvent?
    @State private var isSyncing = false
    @State private var syncErrorMessage: String?
    @State private var showSyncError = false
    @State private var showSyncSuccess = false
    @State private var navigateToUpload = false
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

                        if editableClass.isSample {
                            Text("This is a sample class — nothing here syncs to Google Calendar.")
                                .font(.caption)
                                .foregroundColor(.purple)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.purple.opacity(0.15))
                                .cornerRadius(10)
                                .padding(.horizontal)
                        }

                        // ── Header ────────────────────────────────────────
                        classHeader
                            .coachAnchor(.editDone)

                        // ── Weekly schedule + class-meeting sync ──────────
                        scheduleSection

                        // ── Events list ───────────────────────────────────
                        eventsSection
                            .coachAnchor(.editIntro)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 100) // leave room for the sticky button
                }

                // ── Sticky bottom button ───────────────────────────────
                if !editableClass.isSample {
                    bottomButton
                }
            }
        }
        .navigationTitle(editableClass.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(editableClass.isSample && sampleTour.isActive)
        .coachMarks(sampleTour)
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
            .environmentObject(termStore)
            .environmentObject(sampleTour)
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

            // "Auto-sync class meetings": a class created (or given a schedule by
            // the syllabus parser) while the setting was on has meetingSyncEnabled
            // set but was never pushed — or an earlier auto-push failed. Do it now.
            if !authManager.isGuest,
               !editableClass.isSample,
               editableClass.status != .inactive,
               editableClass.meetingSyncEnabled,
               scheduleHasContent,
               editableClass.meetingEventIds.isEmpty,
               !isSyncingMeetings {
                Task { await syncClassMeetings(isToggleAction: false) }
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

            // Term folder
            if !termStore.terms.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("Term")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Picker("Term", selection: Binding(
                        get: { editableClass.termID },
                        set: { newID in
                            editableClass.termID = newID
                            persistClass()
                        }
                    )) {
                        Text("None").tag(UUID?.none)
                        ForEach(termStore.terms) { term in
                            Text(term.displayName()).tag(Optional(term.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
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

    /// The date the class length counts from: the first class meeting, else the
    /// term start, else today.
    private var lengthAnchor: Date {
        editableClass.structuredSchedule?.firstMeetingDate
            ?? termStore.term(id: editableClass.termID)?.startDate
            ?? Calendar.current.startOfDay(for: Date())
    }

    /// Class length in whole weeks, derived from the end date, or nil when the
    /// class is open-ended. (Shown value can shift if the first-meeting date
    /// later moves — the end date itself stays put until the stepper is used.)
    private var lengthInWeeks: Int? {
        guard let end = editableClass.endDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: lengthAnchor, to: end).day ?? 0
        return max(1, Int((Double(days) / 7.0).rounded()))
    }

    /// Weeks to seed the stepper with the first time a length is set: the term's
    /// length if the class is in one, otherwise a 10-week quarter.
    private var defaultLengthWeeks: Int {
        termStore.term(id: editableClass.termID)?.weeks ?? 10
    }

    private func setLength(weeks: Int) {
        let w = min(max(weeks, 1), 52)
        editableClass.endDate = Calendar.current.date(byAdding: .day, value: w * 7, to: lengthAnchor)
        persistClass()
    }

    /// Only worth showing once the class has something the length actually bounds:
    /// a schedule, a term it inherits an end from, or an end already set.
    private var showsLengthRow: Bool {
        scheduleHasContent || editableClass.termID != nil || editableClass.endDate != nil
    }

    /// How many weeks the class runs — drives the end date, which stops the
    /// recurring meetings and auto-switches the class to INACTIVE.
    private var lengthRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("Class Length")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                if lengthInWeeks == nil {
                    Button("Set length") { setLength(weeks: defaultLengthWeeks) }
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    Button("Open-ended") {
                        editableClass.endDate = nil
                        persistClass()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }

            if let weeks = lengthInWeeks {
                Stepper(value: Binding(get: { weeks }, set: { setLength(weeks: $0) }),
                        in: 1...52) {
                    Text("\(weeks) \(weeks == 1 ? "week" : "weeks")")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
            }

            if let end = editableClass.endDate {
                Text("Ends \(end.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
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

            if !authManager.isGuest && !editableClass.isSample {
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

                if !scheduleHasContent {
                    Text("Set a schedule above first.")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                if showsLengthRow {
                    Divider().background(Color.gray.opacity(0.3))
                    lengthRow
                }
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
        // A colour-only sync: same endpoint, no event changes.
        guard let request = try? ClassSyncRequest.makeRequest(
            email: UserDefaults.standard.string(forKey: "userEmail"),
            className: editableClass.name,
            googleCalendarId: editableClass.googleCalendarId,
            classColorHex: editableClass.colorHex,
            reminderMinutes: settingsManager.reminderMinutes,
            events: []
        ) else { return }

        // Routed through `send` so a revoked token still triggers sign-out,
        // even though the colour sync itself reports nothing to the user.
        _ = try? await authManager.send(request)
    }

    /// Check/uncheck this class's calendar in the user's Google Calendar sidebar.
    private func setCalendarVisibility(selected: Bool) async {
        guard !authManager.isGuest, let calId = editableClass.googleCalendarId else { return }
        await ClassCalendar.setVisibility(calendarId: calId, selected: selected,
                                          send: { try await authManager.send($0) })
    }

    // MARK: - Class meeting sync

    private func syncClassMeetings(isToggleAction: Bool = true) async {
        guard !authManager.isGuest else { return }

        let enabledBefore = editableClass.meetingSyncEnabled
        await MainActor.run { isSyncingMeetings = true }

        let outcome = await ClassMeetingSync.run(
            for: editableClass,
            term: termStore.term(id: editableClass.termID),
            send: { try await authManager.send($0) }
        )

        await MainActor.run {
            isSyncingMeetings = false
            switch outcome {
            case .unauthorized:
                break  // session-expired sign-out already triggered
            case .updated(let updated):
                editableClass = updated
                persistClass()
            case .failed(let message, let clientError):
                meetingSyncError = message
                showMeetingSyncError = true
                // Only revert the toggle for a definite client error; leave it
                // as-is on a 5xx / cold start so a retry doesn't need re-toggling.
                if isToggleAction && clientError {
                    editableClass.meetingSyncEnabled = !enabledBefore
                    persistClass()
                }
            }
        }
    }

    private func resyncChanges() async {
        // Only send events that actually need action (insert / update / delete);
        // unchanged, already-synced events are skipped by `incrementalEvents`.
        let request: URLRequest?
        do {
            request = try ClassSyncRequest.makeRequest(
                email: UserDefaults.standard.string(forKey: "userEmail"),
                className: editableClass.name,
                googleCalendarId: editableClass.googleCalendarId,
                classColorHex: editableClass.colorHex,
                reminderMinutes: settingsManager.reminderMinutes,
                events: ClassSyncRequest.incrementalEvents(from: editableClass.events)
            )
        } catch {
            syncErrorMessage = "Failed to encode sync request."
            showSyncError = true
            return
        }
        guard let request else {
            syncErrorMessage = "Could not determine your account email."
            showSyncError = true
            return
        }

        await MainActor.run { isSyncing = true }

        do {
            let (data, http) = try await authManager.send(request)
            await MainActor.run {
                isSyncing = false
                if http.statusCode == 401 { return }  // session-expired sign-out already triggered
                if http.statusCode == 200,
                   let syncResponse = try? JSONDecoder().decode(ClassSyncRequest.Response.self, from: data) {
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

    private func applySync(response: ClassSyncRequest.Response) {
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
        .environmentObject(TermStore())
        .environmentObject(SampleTour())
    }
}
