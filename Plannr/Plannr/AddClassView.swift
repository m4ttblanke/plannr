//
//  AddClassView.swift
//  Plannr
//
//  Created by Divya Subramonian on 2/12/26.
//

import SwiftUI

struct AddClassView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var classManager: ClassManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var settingsManager: SettingsManager

    @State private var className: String = ""
    @State private var schedule = ClassSchedule()
    @State private var selectedColor: Color = .blue

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) {
                            Text("Add New Class")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            VStack(spacing: 20) {
                                // Class Name
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Class Name")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    TextField("e.g., Advanced Calculus", text: $className)
                                        .padding()
                                        .background(Color.gray.opacity(0.2))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }

                                // Schedule (optional)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Schedule (Optional)")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    ClassSchedulePicker(schedule: $schedule)
                                }

                                // Color picker
                                HStack {
                                    Text("Class Color")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    ColorPicker("", selection: $selectedColor)
                                        .labelsHidden()
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                    }

                    Button {
                        addClass()
                        dismiss()
                    } label: {
                        Text("Add Class")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(className.isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(12)
                    }
                    .disabled(className.isEmpty)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    private func addClass() {
        // "Auto-sync class meetings": a signed-in user who has the setting on gets
        // meeting sync turned on for any class they create with a schedule.
        let autoSyncMeetings = !schedule.isEmpty
            && settingsManager.autoSyncClassMeetings
            && !authManager.isGuest

        let newClass = Class(
            name: className,
            schedule: schedule.displayString,
            colorHex: selectedColor.toHex(),
            endDate: settingsManager.term.resolvedEndDate(),
            structuredSchedule: schedule.isEmpty ? nil : schedule,
            meetingSyncEnabled: autoSyncMeetings
        )
        classManager.addClass(newClass)

        if autoSyncMeetings {
            // Fire-and-forget: if this fails, meetingSyncEnabled stays on and
            // ClassEditView pushes it the next time the class is opened.
            Task {
                let outcome = await ClassMeetingSync.run(
                    for: newClass,
                    settings: settingsManager,
                    send: { try await authManager.send($0) }
                )
                if case .updated(let synced) = outcome {
                    await MainActor.run { classManager.updateClass(synced) }
                }
            }
        }
    }
}

#Preview {
    AddClassView()
        .environmentObject(ClassManager())
        .environmentObject(AuthManager())
        .environmentObject(SettingsManager.shared)
}
