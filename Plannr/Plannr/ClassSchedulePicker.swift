//
//  ClassSchedulePicker.swift
//  Plannr
//
//  Structured input for a class's weekly schedule: which days it meets and at
//  what time, plus an optional discussion/lab section that meets separately
//  (a different day and time). Reads and writes a `ClassSchedule`.
//

import SwiftUI

struct ClassSchedulePicker: View {
    @Binding var schedule: ClassSchedule

    private static var defaultTime: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }

    // Local editing state, projected back onto `schedule` on every change.
    @State private var lectureDays: Set<Weekday> = []
    @State private var lectureTime: Date = ClassSchedulePicker.defaultTime
    @State private var hasSection: Bool = false
    @State private var sectionDays: Set<Weekday> = []
    @State private var sectionTime: Date = ClassSchedulePicker.defaultTime
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            weekdayRow(selection: $lectureDays)

            if !lectureDays.isEmpty {
                timeRow(label: "Class time", selection: $lectureTime)
            }

            Toggle(isOn: $hasSection.animation(.easeInOut(duration: 0.15))) {
                Text("Has a separate section / lab")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .tint(.blue)

            if hasSection {
                Divider().background(Color.gray.opacity(0.3))
                Text("Section")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
                weekdayRow(selection: $sectionDays)
                if !sectionDays.isEmpty {
                    timeRow(label: "Section time", selection: $sectionTime)
                }
            }

            if !schedule.displayString.isEmpty {
                Text(schedule.displayString)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(10)
        .onAppear(perform: loadFromSchedule)
        .onChange(of: lectureDays) { _, _ in pushToSchedule() }
        .onChange(of: lectureTime) { _, _ in pushToSchedule() }
        .onChange(of: hasSection) { _, _ in pushToSchedule() }
        .onChange(of: sectionDays) { _, _ in pushToSchedule() }
        .onChange(of: sectionTime) { _, _ in pushToSchedule() }
    }

    private func loadFromSchedule() {
        guard !didLoad else { return }
        didLoad = true
        lectureDays = Set(schedule.lectureDays.compactMap(Weekday.init(rawValue:)))
        sectionDays = Set(schedule.sectionDays.compactMap(Weekday.init(rawValue:)))
        hasSection = !schedule.sectionDays.isEmpty || schedule.sectionTime != nil
        if let t = schedule.lectureTime { lectureTime = t.date(on: Date()) }
        if let t = schedule.sectionTime { sectionTime = t.date(on: Date()) }
    }

    private func pushToSchedule() {
        var updated = schedule
        updated.lectureDays = lectureDays.map(\.rawValue).sorted()
        updated.lectureTime = lectureDays.isEmpty ? nil : TimeOfDay(from: lectureTime)
        if hasSection {
            updated.sectionDays = sectionDays.map(\.rawValue).sorted()
            updated.sectionTime = sectionDays.isEmpty ? nil : TimeOfDay(from: sectionTime)
        } else {
            updated.sectionDays = []
            updated.sectionTime = nil
        }
        schedule = updated
    }

    private func weekdayRow(selection: Binding<Set<Weekday>>) -> some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                let isOn = selection.wrappedValue.contains(day)
                Button {
                    if isOn { selection.wrappedValue.remove(day) }
                    else { selection.wrappedValue.insert(day) }
                } label: {
                    Text(day.short)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isOn ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(isOn ? Color.blue : Color.gray.opacity(0.25))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func timeRow(label: String, selection: Binding<Date>) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white)
            Spacer()
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .colorScheme(.dark)
        }
    }
}

#Preview {
    struct Harness: View {
        @State var schedule = ClassSchedule()
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack {
                    ClassSchedulePicker(schedule: $schedule)
                    Text("→ \"\(schedule.displayString)\"").foregroundColor(.gray).font(.caption)
                }
                .padding()
            }
        }
    }
    return Harness()
}
