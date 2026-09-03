//
//  Haptics.swift
//  Plannr
//
//  Small wrapper over UIKit feedback generators for the app's key confirmation
//  moments (accepting/declining an event, a sync finishing). No-ops on devices
//  without a Taptic Engine and on the simulator.
//

import UIKit

enum Haptics {

    /// A light "tick" — toggling an event between accepted / declined / pending,
    /// or queueing / un-queueing a delete.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// A sync (or local save) completed.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// A sync failed.
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
