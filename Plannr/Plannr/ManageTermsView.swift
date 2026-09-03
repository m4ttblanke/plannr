//
//  ManageTermsView.swift
//  Plannr
//
//  Create / edit / delete term folders and pick the active one.
//

import SwiftUI

struct ManageTermsView: View {
    @EnvironmentObject var classManager: ClassManager
    @EnvironmentObject var termStore: TermStore
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var settingsManager: SettingsManager

    @State private var editingTerm: Term?

    private func classCount(_ term: Term) -> Int {
        classManager.classes.filter { $0.termID == term.id }.count
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    if termStore.terms.isEmpty {
                        Text("No terms yet. Add one to group your classes by quarter or semester.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.top, 24)
                            .padding(.horizontal, 32)
                    }

                    ForEach(termStore.terms) { term in
                        Button {
                            editingTerm = term
                        } label: {
                            termRow(term)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        let new = Term(system: .quarter)
                        termStore.add(new)
                        editingTerm = new
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("New Term")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
        }
        .navigationTitle("Terms")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingTerm) { term in
            TermEditView(term: term)
                .environmentObject(classManager)
                .environmentObject(termStore)
                .environmentObject(authManager)
                .environmentObject(settingsManager)
        }
    }

    private func termRow(_ term: Term) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(term.displayName())
                    .font(.headline)
                    .foregroundColor(.white)
                if termStore.activeTerm?.id == term.id {
                    Text("ACTIVE")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(6)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundColor(.gray)
            }
            Text(dateRangeText(term))
                .font(.caption)
                .foregroundColor(.gray)
            Text("\(classCount(term)) class\(classCount(term) == 1 ? "" : "es")")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
    }

    private func dateRangeText(_ term: Term) -> String {
        guard let start = term.startDate else { return "\(term.weeks) weeks · no start date set" }
        let s = start.formatted(date: .abbreviated, time: .omitted)
        guard let end = term.resolvedEndDate() else { return "from \(s)" }
        return "\(s) – \(end.formatted(date: .abbreviated, time: .omitted))  ·  \(term.weeks) weeks"
    }
}

// MARK: - Term editor

struct TermEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var classManager: ClassManager
    @EnvironmentObject var termStore: TermStore
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var settingsManager: SettingsManager

    @State private var draft: Term
    @State private var showDeleteConfirm = false
    @State private var showArchiveConfirm = false

    init(term: Term) {
        _draft = State(initialValue: term)
    }

    private var classCount: Int {
        classManager.classes.filter { $0.termID == draft.id }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        field("Name") {
                            TextField(namePlaceholder, text: $draft.name)
                                .padding(10)
                                .background(Color.gray.opacity(0.15))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }

                        field("Length") {
                            Picker("System", selection: Binding(
                                get: { draft.system },
                                set: { setSystem($0) }
                            )) {
                                ForEach(TermSystem.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .colorScheme(.dark)

                            if draft.system == .custom {
                                Stepper("\(draft.weeks) weeks", value: $draft.weeks, in: 1...30)
                                    .foregroundColor(.white)
                            } else {
                                Text("\(draft.weeks) weeks")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }

                        field("Start date") {
                            DatePicker("", selection: Binding(
                                get: { draft.startDate ?? Date() },
                                set: { draft.startDate = $0 }
                            ), displayedComponents: .date)
                            .labelsHidden()
                            .colorScheme(.dark)
                            .foregroundColor(.white)

                            Text(endText)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        field("") {
                            Toggle(isOn: $draft.autoSyncMeetings) {
                                Text("Auto-sync class meetings for this term")
                                    .foregroundColor(.white)
                            }
                            .tint(.yellow)
                            .disabled(authManager.isGuest)
                        }

                        if termStore.activeTerm?.id != draft.id {
                            Button("Make Active Term") {
                                save()
                                termStore.activeTermID = draft.id
                                dismiss()
                            }
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        }

                        Button(role: .destructive) {
                            showArchiveConfirm = true
                        } label: {
                            Text("Archive term (\(classCount) class\(classCount == 1 ? "" : "es") → INACTIVE)")
                        }
                        .font(.subheadline)
                        .disabled(classCount == 0)

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Text("Delete term")
                                .font(.headline)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.15))
                                .cornerRadius(12)
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                }
            }
            .navigationTitle("Term")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }.foregroundColor(.white)
                }
            }
            .confirmationDialog("Delete this term?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete term", role: .destructive) {
                    for cls in classManager.classes where cls.termID == draft.id {
                        var u = cls; u.termID = nil
                        classManager.updateClass(u)
                    }
                    termStore.remove(id: draft.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its \(classCount) class\(classCount == 1 ? "" : "es") won't be deleted — they'll just become unfiled.")
            }
            .confirmationDialog("Archive this term?", isPresented: $showArchiveConfirm, titleVisibility: .visible) {
                Button("Archive", role: .destructive) { archive() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every class in \(draft.displayName()) is marked INACTIVE — its recurring meetings are removed from Google Calendar and its calendar is hidden. You can set a class back to ACTIVE any time.")
            }
        }
    }

    private var namePlaceholder: String {
        let derived = draft.displayName()
        return derived == "Untitled term" ? "e.g. Fall 2026" : derived
    }

    private var endText: String {
        guard let end = draft.resolvedEndDate() else { return "Set a start date to get an end date." }
        return "Ends \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title).font(.headline).foregroundColor(.white)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setSystem(_ system: TermSystem) {
        draft.system = system
        if system != .custom { draft.weeks = system.defaultWeeks }
    }

    private func save() {
        termStore.update(draft)
    }

    /// Mark every class in this term INACTIVE and, for a signed-in user, pull its
    /// meetings from Google Calendar and hide its calendar.
    private func archive() {
        save()
        let affected = classManager.classes.filter { $0.termID == draft.id }
        for cls in affected {
            var u = cls
            u.status = .inactive
            let hadMeetingSync = u.meetingSyncEnabled
            u.meetingSyncEnabled = false
            classManager.updateClass(u)

            guard !authManager.isGuest else { continue }
            let updated = u
            Task {
                if hadMeetingSync {
                    let outcome = await ClassMeetingSync.run(
                        for: updated, term: termStore.term(id: updated.termID),
                        send: { try await authManager.send($0) }
                    )
                    if case .updated(let synced) = outcome {
                        await MainActor.run { classManager.updateClass(synced) }
                    }
                }
                if let calId = updated.googleCalendarId {
                    await ClassCalendar.setVisibility(calendarId: calId, selected: false,
                                                     send: { try await authManager.send($0) })
                }
            }
        }
        dismiss()
    }
}

#Preview {
    NavigationStack { ManageTermsView() }
        .environmentObject(ClassManager())
        .environmentObject(TermStore())
        .environmentObject(AuthManager())
        .environmentObject(SettingsManager.shared)
}
