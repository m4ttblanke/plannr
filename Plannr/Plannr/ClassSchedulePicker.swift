//
//  ClassSchedulePicker.swift
//  Plannr
//
//  Structured input for a class's weekly schedule: which days it meets and the
//  start / end time, plus an optional discussion/lab section that meets
//  separately. Reads and writes a `ClassSchedule`.
//

import SwiftUI

struct ClassSchedulePicker: View {
    @Binding var schedule: ClassSchedule

    private static var defaultStart: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }
    private static var defaultEnd: Date {
        Calendar.current.date(byAdding: .minute, value: defaultMeetingMinutes, to: defaultStart) ?? defaultStart
    }

    // Local editing state, projected back onto `schedule` on every change.
    @State private var lectureDays: Set<Weekday> = []
    @State private var lectureStart: Date = ClassSchedulePicker.defaultStart
    @State private var lectureEnd: Date = ClassSchedulePicker.defaultEnd
    @State private var hasSection: Bool = false
    @State private var sectionDays: Set<Weekday> = []
    @State private var sectionStart: Date = ClassSchedulePicker.defaultStart
    @State private var sectionEnd: Date = ClassSchedulePicker.defaultEnd
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            weekdayRow(selection: $lectureDays)

            if !lectureDays.isEmpty {
                timeRangeRow(startLabel: "Starts", start: $lectureStart, end: $lectureEnd)
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
                    timeRangeRow(startLabel: "Starts", start: $sectionStart, end: $sectionEnd)
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
        .onChange(of: lectureStart) { _, _ in keepEndAfterStart(&lectureEnd, lectureStart); pushToSchedule() }
        .onChange(of: lectureEnd) { _, _ in pushToSchedule() }
        .onChange(of: hasSection) { _, _ in pushToSchedule() }
        .onChange(of: sectionDays) { _, _ in pushToSchedule() }
        .onChange(of: sectionStart) { _, _ in keepEndAfterStart(&sectionEnd, sectionStart); pushToSchedule() }
        .onChange(of: sectionEnd) { _, _ in pushToSchedule() }
    }

    private func keepEndAfterStart(_ end: inout Date, _ start: Date) {
        if end <= start {
            end = Calendar.current.date(byAdding: .minute, value: defaultMeetingMinutes, to: start) ?? start
        }
    }

    private func loadFromSchedule() {
        guard !didLoad else { return }
        didLoad = true
        lectureDays = Set(schedule.lectureDays.compactMap(Weekday.init(rawValue:)))
        sectionDays = Set(schedule.sectionDays.compactMap(Weekday.init(rawValue:)))
        hasSection = !schedule.sectionDays.isEmpty || schedule.sectionStart != nil

        if let s = schedule.lectureStart { lectureStart = s.date(on: Date()) }
        lectureEnd = schedule.lectureEnd?.date(on: Date())
            ?? Calendar.current.date(byAdding: .minute, value: defaultMeetingMinutes, to: lectureStart) ?? lectureStart

        if let s = schedule.sectionStart { sectionStart = s.date(on: Date()) }
        sectionEnd = schedule.sectionEnd?.date(on: Date())
            ?? Calendar.current.date(byAdding: .minute, value: defaultMeetingMinutes, to: sectionStart) ?? sectionStart
    }

    private func pushToSchedule() {
        var updated = schedule
        updated.lectureDays = lectureDays.map(\.rawValue).sorted()
        updated.lectureStart = lectureDays.isEmpty ? nil : TimeOfDay(from: lectureStart)
        updated.lectureEnd = lectureDays.isEmpty ? nil : TimeOfDay(from: lectureEnd)
        if hasSection {
            updated.sectionDays = sectionDays.map(\.rawValue).sorted()
            updated.sectionStart = sectionDays.isEmpty ? nil : TimeOfDay(from: sectionStart)
            updated.sectionEnd = sectionDays.isEmpty ? nil : TimeOfDay(from: sectionEnd)
        } else {
            updated.sectionDays = []
            updated.sectionStart = nil
            updated.sectionEnd = nil
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

    private func timeRangeRow(startLabel: String, start: Binding<Date>, end: Binding<Date>) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(startLabel)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Spacer()
                DatePicker("", selection: start, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .colorScheme(.dark)
            }
            HStack {
                Text("Ends")
                    .font(.subheadline)
                    .foregroundColor(.white)
                Spacer()
                DatePicker("", selection: end, in: start.wrappedValue..., displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .colorScheme(.dark)
            }
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
