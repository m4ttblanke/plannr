//
//  ClassSchedulePicker.swift
//  Plannr
//
//  Structured input for a class's weekly schedule: meeting days with start/end
//  times, an optional section/lab, the first-meeting date, and an optional
//  one-time final exam. Reads and writes a `ClassSchedule`. (How long the class
//  runs is set as a week count on the class itself, not here.)
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
    private static var defaultFinalStart: Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }

    @State private var lectureDays: Set<Weekday> = []
    @State private var lectureStart: Date = ClassSchedulePicker.defaultStart
    @State private var lectureEnd: Date = ClassSchedulePicker.defaultEnd
    @State private var hasSection = false
    @State private var sectionDays: Set<Weekday> = []
    @State private var sectionStart: Date = ClassSchedulePicker.defaultStart
    @State private var sectionEnd: Date = ClassSchedulePicker.defaultEnd

    @State private var firstMeeting: Date = Calendar.current.startOfDay(for: Date())
    @State private var hasFinal = false
    @State private var finalDate: Date = Calendar.current.date(byAdding: .day, value: 77, to: Date()) ?? Date()
    @State private var finalStart: Date = ClassSchedulePicker.defaultFinalStart
    @State private var finalEnd: Date = Calendar.current.date(byAdding: .minute, value: 120,
                                                              to: ClassSchedulePicker.defaultFinalStart) ?? Date()
    @State private var didLoad = false

    private var hasAnyMeeting: Bool { !lectureDays.isEmpty || (hasSection && !sectionDays.isEmpty) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            lectureBlock
            sectionBlock
            if hasAnyMeeting { firstClassBlock }
            if !schedule.displayString.isEmpty {
                Text(schedule.displayString).font(.caption).foregroundColor(.blue).padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(10)
        .onAppear(perform: loadFromSchedule)
    }

    // MARK: - Blocks

    private var lectureBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            weekdayRow(selection: $lectureDays)
            if !lectureDays.isEmpty {
                timeRangeRow(start: $lectureStart, end: $lectureEnd)
            }
            Toggle(isOn: $hasSection.animation(.easeInOut(duration: 0.15))) {
                Text("Has a separate section / lab").font(.subheadline).foregroundColor(.white)
            }
            .tint(.blue)
        }
        .onChange(of: lectureDays) { _, _ in push() }
        .onChange(of: lectureStart) { _, _ in clamp(&lectureEnd, after: lectureStart); push() }
        .onChange(of: lectureEnd) { _, _ in push() }
        .onChange(of: hasSection) { _, _ in push() }
    }

    @ViewBuilder
    private var sectionBlock: some View {
        if hasSection {
            VStack(alignment: .leading, spacing: 14) {
                Divider().background(Color.gray.opacity(0.3))
                Text("Section").font(.caption).fontWeight(.semibold).foregroundColor(.gray)
                weekdayRow(selection: $sectionDays)
                if !sectionDays.isEmpty {
                    timeRangeRow(start: $sectionStart, end: $sectionEnd)
                }
            }
            .onChange(of: sectionDays) { _, _ in push() }
            .onChange(of: sectionStart) { _, _ in clamp(&sectionEnd, after: sectionStart); push() }
            .onChange(of: sectionEnd) { _, _ in push() }
        }
    }

    private var firstClassBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider().background(Color.gray.opacity(0.3))

            HStack {
                Text("First class").font(.subheadline).foregroundColor(.white)
                Spacer()
                DatePicker("", selection: $firstMeeting, displayedComponents: .date)
                    .labelsHidden().colorScheme(.dark)
            }

            Toggle(isOn: $hasFinal.animation(.easeInOut(duration: 0.15))) {
                Text("Add a final exam").font(.subheadline).foregroundColor(.white)
            }
            .tint(.blue)

            if hasFinal {
                Text("A one-time event, usually during finals week after classes end.")
                    .font(.caption2).foregroundColor(.gray)
                HStack {
                    Text("Date").font(.subheadline).foregroundColor(.white)
                    Spacer()
                    DatePicker("", selection: $finalDate, displayedComponents: .date)
                        .labelsHidden().colorScheme(.dark)
                }
                timeRangeRow(start: $finalStart, end: $finalEnd)
            }
        }
        .onChange(of: firstMeeting) { _, _ in push() }
        .onChange(of: hasFinal) { _, _ in push() }
        .onChange(of: finalDate) { _, _ in push() }
        .onChange(of: finalStart) { _, _ in clamp(&finalEnd, after: finalStart); push() }
        .onChange(of: finalEnd) { _, _ in push() }
    }

    // MARK: - State <-> schedule

    private func clamp(_ end: inout Date, after start: Date) {
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

        firstMeeting = schedule.firstMeetingDate ?? Calendar.current.startOfDay(for: Date())
        if let f = schedule.finalExam {
            hasFinal = true
            finalDate = f.date
            finalStart = f.start.date(on: f.date)
            finalEnd = f.end?.date(on: f.date)
                ?? Calendar.current.date(byAdding: .minute, value: 120, to: finalStart) ?? finalStart
        }
    }

    private func push() {
        var s = schedule
        s.lectureDays = lectureDays.map(\.rawValue).sorted()
        s.lectureStart = lectureDays.isEmpty ? nil : TimeOfDay(from: lectureStart)
        s.lectureEnd = lectureDays.isEmpty ? nil : TimeOfDay(from: lectureEnd)
        if hasSection {
            s.sectionDays = sectionDays.map(\.rawValue).sorted()
            s.sectionStart = sectionDays.isEmpty ? nil : TimeOfDay(from: sectionStart)
            s.sectionEnd = sectionDays.isEmpty ? nil : TimeOfDay(from: sectionEnd)
        } else {
            s.sectionDays = []; s.sectionStart = nil; s.sectionEnd = nil
        }

        s.firstMeetingDate = hasAnyMeeting ? Calendar.current.startOfDay(for: firstMeeting) : nil
        s.finalExam = (hasAnyMeeting && hasFinal)
            ? ClassFinalExam(date: Calendar.current.startOfDay(for: finalDate),
                             start: TimeOfDay(from: finalStart), end: TimeOfDay(from: finalEnd))
            : nil

        schedule = s
    }

    // MARK: - Reusable rows

    private func weekdayRow(selection: Binding<Set<Weekday>>) -> some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                let isOn = selection.wrappedValue.contains(day)
                Button {
                    if isOn { selection.wrappedValue.remove(day) } else { selection.wrappedValue.insert(day) }
                } label: {
                    Text(day.short)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(isOn ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(isOn ? Color.blue : Color.gray.opacity(0.25))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func timeRangeRow(start: Binding<Date>, end: Binding<Date>) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Starts").font(.subheadline).foregroundColor(.white)
                Spacer()
                DatePicker("", selection: start, displayedComponents: .hourAndMinute)
                    .labelsHidden().colorScheme(.dark)
            }
            HStack {
                Text("Ends").font(.subheadline).foregroundColor(.white)
                Spacer()
                DatePicker("", selection: end, in: start.wrappedValue..., displayedComponents: .hourAndMinute)
                    .labelsHidden().colorScheme(.dark)
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
                ScrollView {
                    VStack {
                        ClassSchedulePicker(schedule: $schedule)
                        Text("→ \"\(schedule.displayString)\"").foregroundColor(.gray).font(.caption)
                    }.padding()
                }
            }
        }
    }
    return Harness()
}
