//
//  ClassSchedule.swift
//  Plannr
//
//  Structured weekly schedule for a class: the days/time the lecture meets, plus
//  an optional section/lab that meets on its own day and time. Stored on `Class`
//  and used to (a) show a human-readable string, (b) push recurring "class
//  meeting" events to Google Calendar, and (c) optionally list meetings in Week
//  at a Glance.
//

import Foundation

enum Weekday: Int, CaseIterable, Identifiable, Codable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    /// Compact chip / display label.
    var short: String { ["Su", "M", "T", "W", "Th", "F", "Sa"][rawValue - 1] }

    /// iCalendar RRULE BYDAY token.
    var byday: String { ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][rawValue - 1] }

    // Note: rawValue (1 = Sunday … 7 = Saturday) matches
    // Calendar.component(.weekday) for the Gregorian calendar, so no mapping is
    // needed when checking whether a date falls on this weekday.
}

/// Hour and minute of day, independent of any date or time zone.
struct TimeOfDay: Codable, Hashable {
    var hour: Int    // 0...23
    var minute: Int  // 0...59

    static let defaultClassTime = TimeOfDay(hour: 9, minute: 0)

    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    init(from date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 9, minute: c.minute ?? 0)
    }

    /// A Date on `day` at this time.
    func date(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// "9:00 AM"
    var display: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        var comps = DateComponents(); comps.hour = hour; comps.minute = minute
        return f.string(from: Calendar.current.date(from: comps) ?? Date())
    }

    /// "09:00" (24-hour, for the backend).
    var iso: String { String(format: "%02d:%02d", hour, minute) }
}

/// One recurring meeting pattern — the lecture, or the section.
struct ClassMeetingPattern: Hashable {
    enum Kind: String, Codable { case lecture, section }
    var kind: Kind
    var days: [Int]                 // Weekday.rawValue, sorted
    var start: TimeOfDay
    var durationMinutes: Int
}

/// Default meeting length used when only a start time is known.
let defaultMeetingMinutes = 50

struct ClassSchedule: Hashable {
    var lectureDays: [Int] = []
    var lectureStart: TimeOfDay?
    var lectureEnd: TimeOfDay?

    var sectionDays: [Int] = []
    var sectionStart: TimeOfDay?
    var sectionEnd: TimeOfDay?

    init() {}

    var isEmpty: Bool { patterns.isEmpty }

    /// Minutes between a start and end time; `defaultMeetingMinutes` if the end
    /// is missing or not after the start.
    static func duration(from start: TimeOfDay, to end: TimeOfDay?) -> Int {
        guard let end else { return defaultMeetingMinutes }
        let minutes = (end.hour * 60 + end.minute) - (start.hour * 60 + start.minute)
        return minutes > 0 ? minutes : defaultMeetingMinutes
    }

    var patterns: [ClassMeetingPattern] {
        var out: [ClassMeetingPattern] = []
        if !lectureDays.isEmpty, let s = lectureStart {
            out.append(.init(kind: .lecture, days: lectureDays.sorted(), start: s,
                             durationMinutes: Self.duration(from: s, to: lectureEnd)))
        }
        if !sectionDays.isEmpty, let s = sectionStart {
            out.append(.init(kind: .section, days: sectionDays.sorted(), start: s,
                             durationMinutes: Self.duration(from: s, to: sectionEnd)))
        }
        return out
    }

    /// "MWF 9:00 AM – 9:50 AM · Section Th 3:00 PM – 4:15 PM"
    var displayString: String {
        func part(_ days: [Int], _ start: TimeOfDay?, _ end: TimeOfDay?) -> String? {
            guard !days.isEmpty, let start else { return nil }
            let d = days.sorted().compactMap { Weekday(rawValue: $0)?.short }.joined()
            if let end, (end.hour * 60 + end.minute) > (start.hour * 60 + start.minute) {
                return "\(d) \(start.display) – \(end.display)"
            }
            return "\(d) \(start.display)"
        }
        switch (part(lectureDays, lectureStart, lectureEnd),
                part(sectionDays, sectionStart, sectionEnd)) {
        case let (l?, s?): return "\(l) · Section \(s)"
        case let (l?, nil): return l
        case let (nil, s?): return "Section \(s)"
        default: return ""
        }
    }
}

extension ClassSchedule: Codable {
    enum CodingKeys: String, CodingKey {
        case lectureDays, lectureStart, lectureEnd, sectionDays, sectionStart, sectionEnd
        // Legacy keys (start-time + fixed duration), read for migration only.
        case lectureTime, lectureDurationMinutes, sectionTime, sectionDurationMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lectureDays = try c.decodeIfPresent([Int].self, forKey: .lectureDays) ?? []
        sectionDays = try c.decodeIfPresent([Int].self, forKey: .sectionDays) ?? []

        lectureStart = try c.decodeIfPresent(TimeOfDay.self, forKey: .lectureStart)
            ?? (try c.decodeIfPresent(TimeOfDay.self, forKey: .lectureTime))
        lectureEnd = try c.decodeIfPresent(TimeOfDay.self, forKey: .lectureEnd)
            ?? Self.legacyEnd(start: lectureStart,
                              minutes: try c.decodeIfPresent(Int.self, forKey: .lectureDurationMinutes))

        sectionStart = try c.decodeIfPresent(TimeOfDay.self, forKey: .sectionStart)
            ?? (try c.decodeIfPresent(TimeOfDay.self, forKey: .sectionTime))
        sectionEnd = try c.decodeIfPresent(TimeOfDay.self, forKey: .sectionEnd)
            ?? Self.legacyEnd(start: sectionStart,
                              minutes: try c.decodeIfPresent(Int.self, forKey: .sectionDurationMinutes))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lectureDays, forKey: .lectureDays)
        try c.encodeIfPresent(lectureStart, forKey: .lectureStart)
        try c.encodeIfPresent(lectureEnd, forKey: .lectureEnd)
        try c.encode(sectionDays, forKey: .sectionDays)
        try c.encodeIfPresent(sectionStart, forKey: .sectionStart)
        try c.encodeIfPresent(sectionEnd, forKey: .sectionEnd)
    }

    private static func legacyEnd(start: TimeOfDay?, minutes: Int?) -> TimeOfDay? {
        guard let start, let minutes, minutes > 0 else { return nil }
        let total = start.hour * 60 + start.minute + minutes
        return TimeOfDay(hour: (total / 60) % 24, minute: total % 60)
    }
}

/// A concrete meeting on a specific calendar day, for in-app display.
struct ClassMeetingOccurrence: Identifiable {
    let id: String
    let className: String
    let classColorHex: String
    let kind: ClassMeetingPattern.Kind
    let start: Date
    let end: Date
}

extension ClassSchedule {
    /// Meeting occurrences that start within `[from, to)`.
    func occurrences(
        from: Date, to: Date,
        className: String, classColorHex: String, classID: UUID,
        calendar: Calendar = .current
    ) -> [ClassMeetingOccurrence] {
        guard from < to else { return [] }
        var result: [ClassMeetingOccurrence] = []
        let keyFormatter = DateFormatter()
        keyFormatter.dateFormat = "yyyyMMdd"

        for pattern in patterns {
            let targetWeekdays = Set(pattern.days)
            var day = calendar.startOfDay(for: from)
            while day < to {
                if targetWeekdays.contains(calendar.component(.weekday, from: day)) {
                    let start = pattern.start.date(on: day, calendar: calendar)
                    if start >= from && start < to {
                        let end = calendar.date(byAdding: .minute, value: pattern.durationMinutes, to: start) ?? start
                        result.append(ClassMeetingOccurrence(
                            id: "\(classID.uuidString)-\(pattern.kind.rawValue)-\(keyFormatter.string(from: day))",
                            className: className, classColorHex: classColorHex,
                            kind: pattern.kind, start: start, end: end))
                    }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return result.sorted { $0.start < $1.start }
    }
}
