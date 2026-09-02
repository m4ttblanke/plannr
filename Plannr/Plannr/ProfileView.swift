//
//  ProfileView.swift
//  Plannr
//
//  Profile & app settings: photo, current term, reminders, sync behavior,
//  notifications, and account management.
//

import SwiftUI
import PhotosUI

// MARK: - Reusable avatar

struct ProfileAvatarView: View {
    @EnvironmentObject var authManager: AuthManager
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.yellow.opacity(0.3))
                .frame(width: size, height: size)

            if let localData = authManager.localPhotoData, let uiImage = UIImage(data: localData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let urlString = authManager.userPhotoURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    } else {
                        fallbackIcon
                    }
                }
            } else {
                fallbackIcon
            }
        }
    }

    private var fallbackIcon: some View {
        Group {
            if authManager.isGuest {
                Text("G")
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundColor(.yellow)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.36))
                    .foregroundColor(.yellow)
            }
        }
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var classManager: ClassManager
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showDeleteConfirm = false
    @State private var showDeleteFailedAlert = false
    @State private var showNotificationDeniedAlert = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Capsule()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 40, height: 4)
                        .padding(.top, 12)

                    header
                    termSection
                    reminderSection
                    weekViewSection
                    syncSection
                    notificationSection
                    accountSection
                }
                .padding(.bottom, 40)
            }
        }
        .alert("Notifications Disabled", isPresented: $showNotificationDeniedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable notifications for Plannr in the Settings app to get deadline reminders.")
        }
        .alert("Couldn't Delete Account", isPresented: $showDeleteFailedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authManager.errorMessage ?? "Something went wrong. Your account was not deleted — please try again.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                ProfileAvatarView(size: 88)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.caption)
                            .foregroundColor(.black)
                            .padding(6)
                            .background(Circle().fill(Color.yellow))
                    }
            }
            .onChange(of: selectedPhotoItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        authManager.setLocalProfilePhoto(data)
                    }
                }
            }

            if authManager.localPhotoData != nil {
                Button("Remove Custom Photo") {
                    authManager.clearLocalProfilePhoto()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }

            VStack(spacing: 6) {
                if authManager.isGuest {
                    Text("Guest User")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("Sign in to save your data across sessions")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    if let name = authManager.userName {
                        Text(name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    if let email = authManager.userEmail {
                        Text(email)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: Term

    private var termSection: some View {
        SettingsSection(title: "Current Term", icon: "graduationcap.fill") {
            TextField(termLabelPlaceholder, text: Binding(
                get: { settingsManager.term.label },
                set: { settingsManager.term.label = $0 }
            ))
            .padding(10)
            .background(Color.gray.opacity(0.15))
            .foregroundColor(.white)
            .cornerRadius(8)

            Picker("System", selection: Binding(
                get: { settingsManager.term.system },
                set: { setTermSystem($0) }
            )) {
                ForEach(TermSystem.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .colorScheme(.dark)

            DatePicker(
                "Start date",
                selection: Binding(
                    get: { settingsManager.term.startDate ?? Date() },
                    set: { settingsManager.term.startDate = $0 }
                ),
                displayedComponents: .date
            )
            .foregroundColor(.white)
            .colorScheme(.dark)

            if settingsManager.term.system == .custom {
                DatePicker(
                    "End date",
                    selection: Binding(
                        get: { settingsManager.term.endDate ?? settingsManager.term.resolvedEndDate() ?? Calendar.current.date(byAdding: .month, value: 4, to: Date())! },
                        set: { settingsManager.term.endDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .foregroundColor(.white)
                .colorScheme(.dark)
            } else {
                HStack {
                    Text("Ends")
                        .foregroundColor(.white)
                    Spacer()
                    Text(derivedEndText)
                        .foregroundColor(.gray)
                }
            }

            Text("New classes default to this end date. Set it per class from the class screen.")
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }

    private var termLabelPlaceholder: String {
        let derived = settingsManager.term.displayLabel()
        return derived.isEmpty ? "e.g. Fall 2026" : derived
    }

    private var derivedEndText: String {
        guard let end = settingsManager.term.resolvedEndDate() else { return "set a start date" }
        let weeks = settingsManager.term.system.weeks
        let dateText = end.formatted(date: .abbreviated, time: .omitted)
        return weeks.map { "\(dateText)  ·  \($0) weeks" } ?? dateText
    }

    private func setTermSystem(_ newValue: TermSystem) {
        var t = settingsManager.term
        if newValue == .custom {
            if t.endDate == nil { t.endDate = t.resolvedEndDate() }
        } else {
            t.endDate = nil   // let the system's week count drive it
        }
        t.system = newValue
        settingsManager.term = t
    }

    // MARK: Reminders

    private var reminderSection: some View {
        SettingsSection(title: "Deadline Reminders", icon: "bell.badge.fill") {
            Picker("Remind me", selection: Binding(
                get: { settingsManager.reminderLeadTimeDays },
                set: { settingsManager.reminderLeadTimeDays = $0 }
            )) {
                ForEach(reminderLeadTimeOptions, id: \.self) { days in
                    Text(reminderLabel(for: days)).tag(days)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)

            Text("Applied to events as they're synced to Google Calendar.")
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }

    private func reminderLabel(for days: Int) -> String {
        switch days {
        case -1: return "Google default"
        case 0: return "Same day"
        case 1: return "1 day before"
        default: return "\(days) days before"
        }
    }

    // MARK: Class meetings display

    private var weekViewSection: some View {
        SettingsSection(title: "Class Meetings", icon: "calendar.day.timeline.left") {
            Toggle(isOn: Binding(
                get: { settingsManager.showClassMeetingsInCalendar },
                set: { settingsManager.showClassMeetingsInCalendar = $0 }
            )) {
                Text("Show in Calendar")
                    .foregroundColor(.white)
            }
            .tint(.yellow)

            Toggle(isOn: Binding(
                get: { settingsManager.showClassMeetingsInWeekView },
                set: { settingsManager.showClassMeetingsInWeekView = $0 }
            )) {
                Text("Show in Week at a Glance")
                    .foregroundColor(.white)
            }
            .tint(.yellow)

            Text("Whether recurring lecture/section times and final exams appear in those two views. Off by default. They still sync to your Google Calendar when enabled per class.")
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }

    // MARK: Sync

    private var syncSection: some View {
        SettingsSection(title: "Sync", icon: "arrow.triangle.2.circlepath") {
            Toggle(isOn: Binding(
                get: { settingsManager.autoSyncEnabled },
                set: { settingsManager.autoSyncEnabled = $0 }
            )) {
                Text("Auto-sync changes")
                    .foregroundColor(.white)
            }
            .tint(.yellow)
            .disabled(authManager.isGuest)

            Text(authManager.isGuest
                 ? "Not available in guest mode."
                 : "Push edits to Google Calendar immediately instead of waiting for a manual re-sync.")
                .font(.caption2)
                .foregroundColor(.gray)

            Toggle(isOn: Binding(
                get: { settingsManager.autoSyncClassMeetings },
                set: { settingsManager.autoSyncClassMeetings = $0 }
            )) {
                Text("Auto-sync class meetings")
                    .foregroundColor(.white)
            }
            .tint(.yellow)
            .disabled(authManager.isGuest)

            Text(authManager.isGuest
                 ? "Not available in guest mode."
                 : "New classes that have a schedule (typed in, or read from the syllabus) push their lecture/section times to Google Calendar automatically. Existing classes are left as they are.")
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }

    // MARK: Notifications

    private var notificationSection: some View {
        SettingsSection(title: "Notifications", icon: "app.badge.fill") {
            Toggle(isOn: Binding(
                get: { settingsManager.notificationsEnabled },
                set: { newValue in
                    if newValue {
                        NotificationManager.shared.requestAuthorization { granted in
                            settingsManager.notificationsEnabled = granted
                            if !granted { showNotificationDeniedAlert = true }
                        }
                    } else {
                        settingsManager.notificationsEnabled = false
                    }
                }
            )) {
                Text("Deadline reminders")
                    .foregroundColor(.white)
            }
            .tint(.yellow)

            Text("Local notifications on this device, based on the reminder lead time above.")
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }

    // MARK: Account

    private var accountSection: some View {
        VStack(spacing: 12) {
            if !authManager.isGuest {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack {
                        if authManager.isDeletingAccount {
                            ProgressView().tint(.red)
                        } else {
                            Image(systemName: "trash.fill")
                        }
                        Text("Delete Account")
                    }
                    .font(.headline)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.15))
                    .cornerRadius(12)
                }
                .disabled(authManager.isDeletingAccount)
                .padding(.horizontal)
            }

            Button {
                authManager.signOut()
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text(authManager.isGuest ? "Exit Guest Mode" : "Sign Out")
                }
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(red: 1, green: 0.72, blue: 0.11))
                .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task {
                    if await authManager.deleteAccount() {
                        classManager.clearAllData()
                        settingsManager.resetToDefaults()
                        NotificationManager.shared.cancelAll()
                        dismiss()
                    } else {
                        showDeleteFailedAlert = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, stored Google credentials, and all synced data. This cannot be undone.")
        }
    }
}

// MARK: - Settings section container

private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(.yellow)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            content
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthManager())
        .environmentObject(ClassManager())
        .environmentObject(SettingsManager.shared)
}
