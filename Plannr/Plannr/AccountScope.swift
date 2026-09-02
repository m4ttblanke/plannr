//
//  AccountScope.swift
//  Plannr
//
//  Turns a signed-in user's email into a stable token used to namespace their
//  on-device data (saved classes, custom profile photo) so signing out of one
//  Google account and into another doesn't leak the first account's classes.
//

import Foundation

enum AccountScope {
    private static let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-_")

    /// A filesystem- and UserDefaults-safe token for `email`. Lower-cased so
    /// "A@x.com" and "a@x.com" resolve to the same store; other characters are
    /// collapsed to "_". Not reversible and not meant to be — it's a namespace.
    static func token(forEmail email: String) -> String {
        String(email.lowercased().map { allowed.contains($0) ? $0 : "_" })
    }
}
