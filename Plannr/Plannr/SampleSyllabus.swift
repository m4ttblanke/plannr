//
//  SampleSyllabus.swift
//  Plannr
//
//  A built-in course syllabus behind the "Try a sample syllabus" button on the
//  empty state, so a first-time user can watch the whole parse → review → sync
//  flow without hunting for a PDF. Dates are generated relative to today so the
//  sample never goes stale.
//

import Foundation

enum SampleSyllabus {
    static let className = "Astronomy 101 (Sample)"
    static let classColorHex = "AF52DE"   // purple

    private static func termStart(now: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 1
        let startOfToday = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: startOfToday)   // 1 = Sun … 7 = Sat
        var daysUntilNextMonday = (9 - weekday) % 7
        if daysUntilNextMonday == 0 { daysUntilNextMonday = 7 }
        return cal.date(byAdding: .day, value: daysUntilNextMonday, to: startOfToday) ?? startOfToday
    }

    /// The events a real parse of `text()` would return — pre-baked so the sample
    /// never calls Gemini. Dates line up with the syllabus text.
    static func events(now: Date = Date(), calendar: Calendar = .current) -> [CalendarEvent] {
        let start = termStart(now: now, calendar: calendar)
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        func d(_ week: Int, _ offset: Int) -> String {
            df.string(from: calendar.date(byAdding: .day, value: week * 7 + offset, to: start) ?? start)
        }
        let specs: [(String, String, String, Int, Int)] = [
            ("Problem Set 1",                "homework", "Chapters 1–2 — orbital mechanics", 1, 4),
            ("Problem Set 2",                "homework", "Chapter 3 — light and telescopes", 2, 4),
            ("Observation Report 1",         "lab",      "Sketch the Moon's terminator", 3, 2),
            ("Midterm Exam",                 "exam",     "Weeks 1–4, in class", 4, 4),
            ("Research Paper: proposal",     "homework", "One paragraph + three sources", 6, 0),
            ("Problem Set 3",                "homework", "Chapter 5 — the inner planets", 6, 4),
            ("Observation Report 2",         "lab",      "Track a planet over two nights", 7, 2),
            ("Problem Set 4",                "homework", "Chapter 7 — gas giants", 8, 4),
            ("Research Paper: final draft",  "homework", "1500–2000 words", 9, 2),
            ("Final Exam",                   "exam",     "Cumulative, 8:00–11:00 AM", 10, 4),
        ]
        return specs.map { title, type, desc, week, offset in
            var e = CalendarEvent(title: title, date: d(week, offset), type: type, description: desc)
            e.status = .accepted
            return e
        }
    }

    /// The weekly schedule a real parse of `text()` would pull out.
    static func schedule(now: Date = Date(), calendar: Calendar = .current) -> ClassSchedule {
        var s = ClassSchedule()
        s.lectureDays = [2, 4, 6]                              // Mon / Wed / Fri
        s.lectureStart = TimeOfDay(hour: 10, minute: 0)
        s.lectureEnd = TimeOfDay(hour: 10, minute: 50)
        s.sectionDays = [5]                                    // Thu
        s.sectionStart = TimeOfDay(hour: 15, minute: 0)
        s.sectionEnd = TimeOfDay(hour: 15, minute: 50)
        s.firstMeetingDate = termStart(now: now, calendar: calendar)
        return s
    }

    /// A short but realistic syllabus: a stated weekly schedule plus ~10 dated
    /// assignments and exams, anchored to the Monday of next week.
    static func text(now: Date = Date(), calendar: Calendar = .current) -> String {
        var cal = calendar
        cal.firstWeekday = 1

        let termStart = termStart(now: now, calendar: cal)

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEEE, MMMM d, yyyy"

        // A date `week` weeks into the term, offset from its Monday
        // (0 = Monday, 2 = Wednesday, 4 = Friday).
        func day(week: Int, weekdayOffset: Int) -> String {
            let d = cal.date(byAdding: .day, value: week * 7 + weekdayOffset, to: termStart) ?? termStart
            return df.string(from: d)
        }

        let year = cal.component(.year, from: termStart)
        let month = cal.component(.month, from: termStart)
        let season: String
        switch month {
        case 3...5:  season = "Spring"
        case 6...8:  season = "Summer"
        case 9...11: season = "Fall"
        default:     season = "Winter"
        }

        return """
        ASTRO 101 — Introduction to the Solar System
        \(season) \(year)

        Lecture: Monday / Wednesday / Friday, 10:00–10:50 AM, Physics Building Room 214
        Discussion Section: Thursday, 3:00–3:50 PM, Physics Building Room 130
        First day of class: \(day(week: 0, weekdayOffset: 0))

        COURSE SCHEDULE

        Problem Set 1 — due \(day(week: 1, weekdayOffset: 4))
        Problem Set 2 — due \(day(week: 2, weekdayOffset: 4))
        Observation Report 1 — due \(day(week: 3, weekdayOffset: 2))
        Midterm Exam — \(day(week: 4, weekdayOffset: 4)), in class
        Research Paper: proposal — due \(day(week: 6, weekdayOffset: 0))
        Problem Set 3 — due \(day(week: 6, weekdayOffset: 4))
        Observation Report 2 — due \(day(week: 7, weekdayOffset: 2))
        Problem Set 4 — due \(day(week: 8, weekdayOffset: 4))
        Research Paper: final draft — due \(day(week: 9, weekdayOffset: 2))
        Final Exam — \(day(week: 10, weekdayOffset: 4)), 8:00–11:00 AM

        GRADING
        Problem Sets 30%, Observation Reports 15%, Midterm 20%,
        Research Paper 15%, Final Exam 20%.
        """
    }
}
