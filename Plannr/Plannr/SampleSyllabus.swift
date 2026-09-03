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
    static let className = "Sample Syllabus"
    static let classColorHex = "AF52DE"   // purple

    /// A short but realistic syllabus: a stated weekly schedule plus ~10 dated
    /// assignments and exams, anchored to the Monday of next week.
    static func text(now: Date = Date(), calendar: Calendar = .current) -> String {
        var cal = calendar
        cal.firstWeekday = 1

        let startOfToday = cal.startOfDay(for: now)
        let weekday = cal.component(.weekday, from: startOfToday)   // 1 = Sun … 7 = Sat
        var daysUntilNextMonday = (9 - weekday) % 7                 // 0 when today is Monday
        if daysUntilNextMonday == 0 { daysUntilNextMonday = 7 }
        let termStart = cal.date(byAdding: .day, value: daysUntilNextMonday, to: startOfToday) ?? startOfToday

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
