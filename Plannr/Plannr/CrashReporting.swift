//
//  CrashReporting.swift
//  Plannr
//
//  Thin wrapper around the Sentry SDK for beta crash reports. Everything here is
//  a no-op unless a DSN is configured (Info.plist `SENTRY_DSN`), so the app runs
//  identically in local development and CI, and the repo carries no DSN.
//
//  Setup: see docs/CRASH_REPORTING.md.
//

import Foundation
import Sentry

enum CrashReporting {

    /// True once a DSN has been supplied — gates every call below.
    static var isEnabled: Bool { !dsn.isEmpty }

    private static var dsn: String {
        (Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Start Sentry. Call once, as early as possible (`PlannrApp.init`).
    static func start() {
        guard isEnabled else {
            #if DEBUG
            print("[CrashReporting] no SENTRY_DSN — crash reporting disabled.")
            #endif
            return
        }
        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = release
            options.environment = environment
            options.enableAutoSessionTracking = true
            options.attachStacktrace = true
            // Crash + error reporting only for the beta — no tracing / profiling.
            options.tracesSampleRate = 0.0
            #if DEBUG
            options.debug = true
            #endif
        }
    }

    /// Associate future events with a signed-in account, or pass `nil` to clear
    /// it (guest mode / sign-out).
    static func setUser(email: String?) {
        guard isEnabled else { return }
        if let email, !email.isEmpty {
            let user = User()
            user.email = email
            SentrySDK.setUser(user)
        } else {
            SentrySDK.setUser(nil)
        }
    }

    /// Leave a breadcrumb so a later crash report has context.
    static func breadcrumb(_ message: String, category: String = "app") {
        guard isEnabled else { return }
        let crumb = Breadcrumb(level: .info, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }

    /// Report a handled error without crashing.
    static func capture(_ error: Error) {
        guard isEnabled else { return }
        SentrySDK.capture(error: error)
    }

    #if DEBUG
    /// Hard-crash on purpose to verify the pipeline end to end (Debug builds only).
    static func triggerTestCrash() {
        SentrySDK.crash()
    }
    #endif

    private static var release: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "plannr@\(version)+\(build)"
    }

    private static var environment: String {
        #if DEBUG
        return "debug"
        #else
        return "production"
        #endif
    }
}
