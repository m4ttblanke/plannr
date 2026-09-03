//
//  Accessibility.swift
//  Plannr
//
//  Small helpers for VoiceOver / Dynamic Type.
//

import SwiftUI

enum A11y {
    /// A spoken label for a calendar day cell — "Wednesday, March 4, 2 events".
    static func dayCellLabel(_ date: Date, eventCount: Int, includeWeekday: Bool) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(includeWeekday ? "EEEEMMMMd" : "MMMMd")
        var label = f.string(from: date)
        if eventCount > 0 {
            label += ", \(eventCount) event\(eventCount == 1 ? "" : "s")"
        }
        return label
    }
}

extension View {
    /// Make a day cell one VoiceOver element: a button with a spoken date +
    /// event count, marked selected when it is.
    func dayCellAccessibility(date: Date, eventCount: Int,
                              includeWeekday: Bool, isSelected: Bool) -> some View {
        self.accessibilityElement(children: .ignore)
            .accessibilityLabel(A11y.dayCellLabel(date, eventCount: eventCount, includeWeekday: includeWeekday))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint("Shows this day's events")
    }
}
