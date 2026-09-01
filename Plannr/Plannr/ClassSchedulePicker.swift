//
//  ClassSchedulePicker.swift
//  Plannr
//
//  Structured input for a class's weekly schedule: which days it meets and at
//  what time, plus an optional discussion/lab section that meets separately
//  (a different day and time). The selection is serialized to a display string
//  (e.g. "MWF 10:00 AM · Section Th 3:00 PM") written back through `schedule`.
//

import SwiftUI

enum Weekday: Int, CaseIterable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    /// Compact label used in the serialized schedule string and on the chips.
    var short: String {
        ["Su", "M", "T", "W", "Th", "F", "Sa"][rawValue - 1]
    }
}

struct ClassSchedulePicker: View {
    /// Formatted, human-readable schedule. Empty when no days are chosen.
    @Binding var schedule: String

    @State private var lectureDays: Set<Weekday> = []
    @State private var lectureTime: Date = ClassSchedulePicker.defaultTime
    @State private var hasSection: Bool = false
    @State private var sectionDays: Set<Weekday> = []
    @State private var sectionTime: Date = ClassSchedulePicker.defaultTime

    private static var defaultTime: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private var composed: String {
        let lecture = Self.format(days: lectureDays, time: lectureTime)
        guard hasSection, !sectionDays.isEmpty else { return lecture }
        let section = Self.format(days: sectionDays, time: sectionTime)
        return lecture.isEmpty ? "Section \(section)" : "\(lecture) · Section \(section)"
    }

    private static func format(days: Set<Weekday>, time: Date) -> String {
        guard !days.isEmpty else { return "" }
        let ordered = Weekday.allCases.filter(days.contains).map(\.short).joined()
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return "\(ordered) \(formatter.string(from: time))"
    }

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

            if !composed.isEmpty {
                Text(composed)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(10)
        .onChange(of: composed) { _, newValue in schedule = newValue }
        .onAppear { schedule = composed }
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
        @State var schedule = ""
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack {
                    ClassSchedulePicker(schedule: $schedule)
                    Text("schedule = \"\(schedule)\"").foregroundColor(.gray).font(.caption)
                }
                .padding()
            }
        }
    }
    return Harness()
}
