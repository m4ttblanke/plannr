//
//  PDFUploadView.swift
//  Plannr
//
//  Created by Divya Subramonian on 1/21/26.
//

import SwiftUI
import MessageUI

enum AppTab {
    case myClasses, calendar, weeklyDashboard
}

/// Which classes the My Classes list shows.
enum ClassScope: Hashable {
    case all
    case term(UUID)
    case unfiled
}

struct PDFUploadView: View {
    @StateObject private var classManager: ClassManager
    @StateObject private var termStore: TermStore
    @StateObject private var settingsManager = SettingsManager.shared
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAddClass = false
    @State private var navigationPath = NavigationPath()
    @State private var selectedTab: AppTab = .myClasses
    @State private var showProfileSheet = false
    @State private var hasSetInitialTab = false
    @State private var hasRunTermMigration = false
    @State private var classScope: ClassScope = .all
    @State private var showManageTerms = false
    @State private var showMailComposer = false
    @State private var showFeedbackFallbackAlert = false
    @State private var feedbackKind: ReportIssue.Kind = .issue

    init(isGuest: Bool = false, accountEmail: String? = nil) {
        _classManager = StateObject(wrappedValue: ClassManager(isGuest: isGuest, accountEmail: accountEmail))
        _termStore = StateObject(wrappedValue: TermStore(isGuest: isGuest, accountEmail: accountEmail))
    }

    // Computed property to determine default tab based on whether user has classes
    private var defaultTab: AppTab {
        return classManager.classes.isEmpty ? .myClasses : .weeklyDashboard
    }

    /// The name shown under the My Classes title — the selected scope, or the
    /// current term when scope is "All". Empty when there are no classes/terms.
    private var termLabel: String {
        guard !classManager.classes.isEmpty else { return "" }
        switch classScope {
        case .all:       return termStore.activeTerm?.displayName() ?? ""
        case .unfiled:   return "Unfiled"
        case .term(let id): return termStore.term(id: id)?.displayName() ?? ""
        }
    }

    /// Classes visible in the My Classes list, per the term scope.
    private var scopedClasses: [Class] {
        switch classScope {
        case .all:          return classManager.classes
        case .unfiled:      return classManager.classes.filter { $0.termID == nil }
        case .term(let id): return classManager.classes.filter { $0.termID == id }
        }
    }

    private var scopeTitle: String {
        switch classScope {
        case .all:          return "All classes"
        case .unfiled:      return "Unfiled"
        case .term(let id): return termStore.term(id: id)?.displayName() ?? "Term"
        }
    }

    @ViewBuilder
    private var termScopeMenu: some View {
        Menu {
            Picker("Scope", selection: $classScope) {
                Text("All classes").tag(ClassScope.all)
                ForEach(termStore.terms) { term in
                    Text(term.displayName()).tag(ClassScope.term(term.id))
                }
                if classManager.classes.contains(where: { $0.termID == nil }) {
                    Text("Unfiled").tag(ClassScope.unfiled)
                }
            }
            Divider()
            Button {
                showManageTerms = true
            } label: {
                Label("Manage terms…", systemImage: "folder.badge.gearshape")
            }
        } label: {
            HStack(spacing: 4) {
                Text(termLabel.isEmpty ? scopeTitle : termLabel)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline)
            .foregroundColor(.gray)
        }
        .onChange(of: classScope) { _, newValue in
            if case .term(let id) = newValue { termStore.activeTermID = id }
        }
    }

    /// One-time: seed a term from the Phase-1 single `TermSettings` and file the
    /// existing (unfiled) classes into it, so upgrading users keep continuity.
    private func runTermMigrationIfNeeded() {
        guard !hasRunTermMigration else { return }
        hasRunTermMigration = true
        guard termStore.terms.isEmpty,
              settingsManager.term.startDate != nil,
              !classManager.classes.isEmpty else { return }

        let term = Term(seedingFrom: settingsManager.term)
        termStore.add(term)
        termStore.activeTermID = term.id
        for cls in classManager.classes where cls.termID == nil {
            var updated = cls
            updated.termID = term.id
            classManager.updateClass(updated)
        }
        // Consume the legacy settings so this never runs twice.
        settingsManager.term = TermSettings()
        classScope = .term(term.id)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Guest mode banner
                    if authManager.isGuest {
                        HStack(spacing: 8) {
                            Image(systemName: "person.slash.fill")
                                .font(.caption)
                            Text("Guest Mode - data won't be saved between sessions")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color(red: 1, green: 0.72, blue: 0.11))
                    }

                    // Header
                    HStack {
                        Menu {
                            Button(action: { selectedTab = .myClasses }) {
                                Label("My Classes", systemImage: "list.bullet")
                            }
                            Button(action: { selectedTab = .calendar }) {
                                Label("Calendar", systemImage: "calendar")
                            }
                            Button(action: { selectedTab = .weeklyDashboard }) {
                                Label("Week at a Glance", systemImage: "chart.bar.doc.horizontal")
                            }

                            Divider()

                            Button(action: { sendFeedback(.issue) }) {
                                Label("Report an Issue", systemImage: "exclamationmark.bubble")
                            }
                            Button(action: { sendFeedback(.feature) }) {
                                Label("Suggest a Feature", systemImage: "lightbulb")
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        .accessibilityLabel("Menu")
                        .accessibilityIdentifier("menuButton")

                        VStack(alignment: .leading, spacing: 0) {
                            Text(selectedTab == .myClasses ? "My Classes" : selectedTab == .calendar ? "Calendar" : "Week at a Glance")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .accessibilityIdentifier("tabTitle")

                            if selectedTab == .myClasses {
                                termScopeMenu
                            }
                        }
                        .padding(.leading, 8)

                        Spacer()

                        // User profile button
                        Button {
                            showProfileSheet = true
                        } label: {
                            ProfileAvatarView(size: 44)
                                .environmentObject(authManager)
                        }
                        .accessibilityLabel("Profile")
                        .accessibilityIdentifier("profileButton")
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                    if selectedTab == .myClasses {
                        ScrollView {
                            VStack(spacing: 16) {
                                // Existing classes (filtered by the term scope)
                                if !scopedClasses.isEmpty {
                                    ForEach(scopedClasses) { classItem in
                                        NavigationLink(value: classItem) {
                                            ClassCard(classItem: classItem)
                                                .environmentObject(classManager)
                                                .environmentObject(authManager)
                                                .environmentObject(termStore)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal)
                                    }
                                } else if !classManager.classes.isEmpty {
                                    Text(classScope == .unfiled ? "No unfiled classes." : "No classes in this term yet.")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .padding(.top, 8)
                                }

                                // Add New Class Button
                                Button {
                                    showAddClass = true
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Add New Class")
                                    }
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(12)
                                }
                                .padding(.horizontal)
                                .padding(.top, 8)
                            }
                            .padding(.bottom, 40)
                        }
                    } else if selectedTab == .calendar {
                        UnifiedCalendarView()
                            .environmentObject(classManager)
                            .environmentObject(termStore)
                    } else if selectedTab == .weeklyDashboard {
                        WeeklyDashboardView()
                            .environmentObject(classManager)
                            .environmentObject(termStore)
                    }
                }
            }
            .onAppear {
                // Only pick the default tab on first launch — not every time this view
                // reappears (e.g. popping back from a pushed class via the back arrow),
                // which would otherwise bounce the user off whatever tab they were on.
                if !hasSetInitialTab {
                    hasSetInitialTab = true
                    selectedTab = defaultTab
                }
                runTermMigrationIfNeeded()
                syncNotifications()
            }
            .onChange(of: classManager.classes) { _, _ in syncNotifications() }
            .onChange(of: settingsManager.notificationsEnabled) { _, _ in syncNotifications() }
            .onChange(of: settingsManager.reminderLeadTimeDays) { _, _ in syncNotifications() }
            // Re-sync on every foreground so the "nearest 60" reminder window
            // rolls forward as earlier ones fire (iOS caps pending reminders at 64).
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { syncNotifications() }
            }
            .navigationDestination(for: Class.self) { cls in
                ClassEditView(cls: cls, onSyncComplete: { navigationPath = NavigationPath() })
                    .environmentObject(classManager)
                    .environmentObject(authManager)
                    .environmentObject(settingsManager)
                    .environmentObject(termStore)
            }
            .navigationDestination(isPresented: $showManageTerms) {
                ManageTermsView()
                    .environmentObject(classManager)
                    .environmentObject(termStore)
                    .environmentObject(authManager)
                    .environmentObject(settingsManager)
            }
            .sheet(isPresented: $showAddClass) {
                AddClassView()
                    .environmentObject(classManager)
                    .environmentObject(authManager)
                    .environmentObject(settingsManager)
                    .environmentObject(termStore)
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileView()
                    .environmentObject(authManager)
                    .environmentObject(classManager)
                    .environmentObject(settingsManager)
                    .environmentObject(termStore)
            }
            .sheet(isPresented: $showMailComposer) {
                MailComposeView(
                    recipient: ReportIssue.recipient,
                    subject: feedbackKind.subject,
                    body: ReportIssue.body(kind: feedbackKind, accountDescription: accountDescription),
                    onFinish: { showMailComposer = false }
                )
                .ignoresSafeArea()
            }
            .alert(feedbackKind.title, isPresented: $showFeedbackFallbackAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This device has no email set up. Please email \(ReportIssue.recipient) directly.")
            }
        }
    }

    private var accountDescription: String {
        authManager.isGuest ? "Guest" : (authManager.userEmail ?? "Signed in")
    }

    /// Opens the in-app mail composer for the given feedback kind, falling back to
    /// the system mail client, then to an alert with the address if neither works.
    private func sendFeedback(_ kind: ReportIssue.Kind) {
        feedbackKind = kind
        if MFMailComposeViewController.canSendMail() {
            showMailComposer = true
        } else if !ReportIssue.openMailto(kind: kind, accountDescription: accountDescription) {
            showFeedbackFallbackAlert = true
        }
    }

    private func syncNotifications() {
        NotificationManager.shared.sync(
            classes: classManager.classes,
            notificationsEnabled: settingsManager.notificationsEnabled,
            leadDays: settingsManager.reminderLeadTimeDays
        )
    }
}

struct ClassCard: View {
    let classItem: Class
    @EnvironmentObject var classManager: ClassManager
    @EnvironmentObject var authManager: AuthManager
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Color bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(classItem.color)
                    .frame(width: 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(classItem.name)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    if !classItem.schedule.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption)
                            Text(classItem.schedule)
                                .font(.caption)
                        }
                        .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Status badge
                switch classItem.status {
                case .noSyllabus:
                    Text("NO SYLLABUS")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(8)
                case .active:
                    Text("ACTIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(classItem.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(classItem.color.opacity(0.2))
                        .cornerRadius(8)
                case .inactive:
                    Text("INACTIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                
                // Delete button
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                .padding(.leading, 8)
            }
            
            // Event count / upload prompt
            switch classItem.status {
            case .noSyllabus:
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.doc")
                        .font(.caption)
                    Text("Tap to upload syllabus")
                        .font(.caption)
                }
                .foregroundColor(.orange.opacity(0.8))
            case .active:
                let visibleCount = classItem.events.filter { !$0.isDeletedLocally }.count
                Text("\(visibleCount) events synced")
                    .font(.caption)
                    .foregroundColor(.gray)
            case .inactive:
                let visibleCount = classItem.events.filter { !$0.isDeletedLocally }.count
                Text("\(visibleCount) events")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
        .confirmationDialog(
            "Delete \(classItem.name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteClass() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func deleteClass() async {
        // Delete the secondary Google Calendar first (best-effort; local delete proceeds regardless)
        if let calId = classItem.googleCalendarId,
           !authManager.isGuest,
           let email = UserDefaults.standard.string(forKey: "userEmail"),
           let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let encodedCalId = calId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "\(BACKEND_URL)calendar?email=\(encodedEmail)&google_calendar_id=\(encodedCalId)") {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            // Via `send` so a revoked token still triggers the global sign-out.
            _ = try? await authManager.send(request)
        }
        classManager.removeClass(classItem)
    }
}

#Preview {
    PDFUploadView()
}

// MARK: - Models

enum EventStatus: String, Codable {
    case pending
    case accepted
    case declined
}

/// The standard event categories. `CalendarEvent.type` is stored as its raw
/// string (so parser output and older data still decode); this normalizes any
/// value to one of the known cases and drives the edit-screen picker.
enum EventType: String, CaseIterable, Identifiable {
    case homework, exam, quiz, lab, other

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    init(_ raw: String) {
        self = EventType(rawValue: raw.lowercased().trimmingCharacters(in: .whitespaces)) ?? .other
    }
}

struct CalendarEvent: Codable, Identifiable {
    let id: UUID
    var title: String
    var date: String
    var type: String
    var description: String
    var colorHex: String = "007AFF"
    var status: EventStatus = .pending
    var isSyllabus: Bool = true
    var isEdited: Bool = false
    var isTaskCompleted: Bool = false
    var googleEventId: String? = nil
    var isDeletedLocally: Bool = false

    var color: Color {
        get { Color(hex: colorHex) }
        set { colorHex = newValue.toHex() }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, date, type, description, colorHex, status, isSyllabus, isEdited, isTaskCompleted, googleEventId, isDeletedLocally
    }

    init(title: String, date: String, type: String, description: String) {
        self.id = UUID()
        self.title = title
        self.date = date
        self.type = type
        self.description = description
    }

    /// Explicit id — used to synthesize stable, non-persisted events (class meetings).
    init(id: UUID, title: String, date: String, type: String, description: String) {
        self.id = id
        self.title = title
        self.date = date
        self.type = type
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "other"
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "007AFF"
        status = try container.decodeIfPresent(EventStatus.self, forKey: .status) ?? .pending
        // isSyllabus is occasionally emitted by the LLM as a string ("true"/"True") rather
        // than a JSON boolean, so fall back to parsing a string before defaulting.
        if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: .isSyllabus) {
            isSyllabus = boolValue
        } else {
            let stringValue = try container.decodeIfPresent(String.self, forKey: .isSyllabus)
            isSyllabus = stringValue.map { $0.lowercased() == "true" } ?? true
        }
        isEdited = try container.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
        isTaskCompleted = try container.decodeIfPresent(Bool.self, forKey: .isTaskCompleted) ?? false
        googleEventId = try container.decodeIfPresent(String.self, forKey: .googleEventId)
        isDeletedLocally = try container.decodeIfPresent(Bool.self, forKey: .isDeletedLocally) ?? false
    }
}

struct SyllabusResponse: Codable {
    let message: String?
    let filename: String?
    let size: Int?
    let events: [CalendarEvent]
    /// Recurring meeting pattern the parser found in the syllabus, if any.
    let schedule: ParsedSchedule?
}

/// The `schedule` object from `POST /syllabus` — the class's meeting days/times
/// as pulled from the syllabus. Any field may be absent. See
/// `ParsedSchedule.toClassSchedule()` for the mapping into `ClassSchedule`.
struct ParsedSchedule: Codable {
    var lectureDays: [String] = []
    var lectureStart: String?
    var lectureEnd: String?
    var sectionDays: [String] = []
    var sectionStart: String?
    var sectionEnd: String?
    var finalDate: String?
    var finalStart: String?
    var finalEnd: String?

    enum CodingKeys: String, CodingKey {
        case lectureDays = "lecture_days"
        case lectureStart = "lecture_start"
        case lectureEnd = "lecture_end"
        case sectionDays = "section_days"
        case sectionStart = "section_start"
        case sectionEnd = "section_end"
        case finalDate = "final_date"
        case finalStart = "final_start"
        case finalEnd = "final_end"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lectureDays = try c.decodeIfPresent([String].self, forKey: .lectureDays) ?? []
        lectureStart = try c.decodeIfPresent(String.self, forKey: .lectureStart)
        lectureEnd = try c.decodeIfPresent(String.self, forKey: .lectureEnd)
        sectionDays = try c.decodeIfPresent([String].self, forKey: .sectionDays) ?? []
        sectionStart = try c.decodeIfPresent(String.self, forKey: .sectionStart)
        sectionEnd = try c.decodeIfPresent(String.self, forKey: .sectionEnd)
        finalDate = try c.decodeIfPresent(String.self, forKey: .finalDate)
        finalStart = try c.decodeIfPresent(String.self, forKey: .finalStart)
        finalEnd = try c.decodeIfPresent(String.self, forKey: .finalEnd)
    }

    /// Map into a `ClassSchedule`, keeping only the parts that are actually
    /// usable (days paired with a start time; a final date for a final exam).
    /// Returns nil when nothing usable came back.
    func toClassSchedule() -> ClassSchedule? {
        func days(_ tokens: [String]) -> [Int] {
            tokens.compactMap { Weekday(byday: $0)?.rawValue }.sorted()
        }

        var schedule = ClassSchedule()

        let lectureDayInts = days(lectureDays)
        if !lectureDayInts.isEmpty, let start = lectureStart.flatMap(TimeOfDay.init(iso:)) {
            schedule.lectureDays = lectureDayInts
            schedule.lectureStart = start
            schedule.lectureEnd = lectureEnd.flatMap(TimeOfDay.init(iso:))
        }

        let sectionDayInts = days(sectionDays)
        if !sectionDayInts.isEmpty, let start = sectionStart.flatMap(TimeOfDay.init(iso:)) {
            schedule.sectionDays = sectionDayInts
            schedule.sectionStart = start
            schedule.sectionEnd = sectionEnd.flatMap(TimeOfDay.init(iso:))
        }

        if let finalDate, let date = ParsedSchedule.isoDateFormatter.date(from: finalDate) {
            let start = finalStart.flatMap(TimeOfDay.init(iso:)) ?? TimeOfDay(hour: 9, minute: 0)
            schedule.finalExam = ClassFinalExam(
                date: Calendar.current.startOfDay(for: date),
                start: start,
                end: finalEnd.flatMap(TimeOfDay.init(iso:))
            )
        }

        return schedule.isEmpty ? nil : schedule
    }

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB (24-bit)
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8: // ARGB (32-bit)
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        // getRed(...) normalizes any color space (grayscale, P3, …). cgColor.components
        // could return fewer than 3 entries for a grayscale color, which crashed on
        // components[1] / components[2].
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return "007AFF" }

        return String(format: "%02lX%02lX%02lX",
                     lroundf(Float(r) * 255),
                     lroundf(Float(g) * 255),
                     lroundf(Float(b) * 255))
    }
}
