//
//  AuthManager.swift
//  Plannr
//
//  Manages Google OAuth authentication state
//

import SwiftUI
import AuthenticationServices

class AuthManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isGuest: Bool = false
    @Published var userEmail: String?
    @Published var userName: String?
    @Published var userPhotoURL: String?
    @Published var localPhotoData: Data?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isDeletingAccount: Bool = false

    /// Pre-scoping device-wide photo filename. Migrated to a per-account file the
    /// first time a signed-in session initializes.
    private static let legacyPhotoFilename = "profile_photo.jpg"

    init() {
        // UI tests launch with -uiTestReset to start from a clean, signed-out
        // state regardless of what a previous run (or manual use) left behind.
        if CommandLine.arguments.contains("-uiTestReset") {
            let defaults = UserDefaults.standard
            for key in ["userEmail", "userName", "userPhotoURL", "savedClasses",
                        "settings.term", "settings.reminderLeadTimeDays",
                        "settings.autoSyncEnabled", "settings.notificationsEnabled",
                        "settings.showClassMeetingsInWeekView",
                        "settings.showClassMeetingsInCalendar",
                        "settings.autoSyncClassMeetings"] {
                defaults.removeObject(forKey: key)
            }
            // Per-account class + term stores written by real sign-ins.
            for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("savedClasses.") || key.hasPrefix("terms.") {
                defaults.removeObject(forKey: key)
            }
            if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
               let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                for file in files where file.hasPrefix("profile_photo") {
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
                }
            }
        }

        // Check if user is already authenticated (from UserDefaults)
        if let email = UserDefaults.standard.string(forKey: "userEmail") {
            self.userEmail = email
            self.userName = UserDefaults.standard.string(forKey: "userName")
            self.userPhotoURL = UserDefaults.standard.string(forKey: "userPhotoURL")
            self.isAuthenticated = true
            CrashReporting.setUser(email: email)
            // Backfill/refresh name + photo from Google for sessions that predate
            // (or whose cached values are stale relative to) these fields.
            refreshGoogleProfile()
        }
        migrateLegacyPhotoIfNeeded()
        self.localPhotoData = loadLocalPhotoData()
    }

    /// Re-fetch the current Google profile (name, picture) using the account's stored
    /// credentials, without requiring the user to sign out and back in.
    func refreshGoogleProfile() {
        guard !isGuest, let email = userEmail,
              let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(BACKEND_URL)me?email=\(encodedEmail)") else { return }

        struct MeResponse: Decodable {
            let email: String
            let name: String
            let picture: String
        }

        Task {
            // Routed through `send` so a 401 (revoked/expired Google credentials)
            // triggers the global session-expired sign-out. This runs on every
            // launch, so it's the main place that condition gets caught.
            guard let (data, http) = try? await self.send(URLRequest(url: url)),
                  http.statusCode == 200,
                  let me = try? JSONDecoder().decode(MeResponse.self, from: data) else { return }

            await MainActor.run {
                if !me.name.isEmpty {
                    self.userName = me.name
                    UserDefaults.standard.set(me.name, forKey: "userName")
                }
                if !me.picture.isEmpty {
                    self.userPhotoURL = me.picture
                    UserDefaults.standard.set(me.picture, forKey: "userPhotoURL")
                }
            }
        }
    }

    /// Called when the backend reports the Google session is no longer valid
    /// (refresh token revoked or expired). Clears the session and surfaces a
    /// message so the UI drops back to the sign-in screen.
    func handleSessionExpired() {
        DispatchQueue.main.async {
            guard self.isAuthenticated, !self.isGuest else { return }
            self.signOut()
            self.errorMessage = "Your Google session expired. Please sign in again."
        }
    }

    /// Networking seam. Backs both `send` and `deleteAccount`; tests replace it
    /// to simulate responses / timeouts. `URLSession.shared` is touched nowhere
    /// else in the app.
    var httpDataProvider: (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(for: $0)
    }

    /// Total attempts `send` makes for one request before giving up on a
    /// *transient* failure (5xx / 429 / a connection-level error). 1 disables retry.
    var maxSendAttempts = 3

    /// Backoff wait between attempts. Replaced in tests so they don't actually sleep.
    var retrySleep: (TimeInterval) async throws -> Void = { seconds in
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    /// The single choke point for **every** backend request. Any 401 response —
    /// from any endpoint — triggers the global session-expired sign-out. Callers
    /// still handle their own non-401 status codes, and should bail out early
    /// (without showing their own error UI) when `http.statusCode == 401`.
    ///
    /// Transient failures — HTTP 5xx / 429, or a connection-level `URLError`
    /// (timeout, connection lost, host unreachable — e.g. a Render dyno waking) —
    /// are retried up to `maxSendAttempts` times with exponential backoff + jitter,
    /// honouring `Retry-After` when present. A 401, any other 4xx, and a
    /// non-`URLError` throw are returned/propagated immediately.
    ///
    /// The one deliberate bypass is `deleteAccount`, which calls
    /// `httpDataProvider` directly: there a 401 means "the account is already
    /// gone", not "session expired". Every other network call goes through here.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            attempt += 1
            let canRetry = attempt < maxSendAttempts
            do {
                let (data, response) = try await httpDataProvider(request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if http.statusCode == 401 {
                    handleSessionExpired()
                    return (data, http)
                }
                if canRetry, Self.isRetryable(status: http.statusCode) {
                    let hint = http.value(forHTTPHeaderField: "Retry-After")
                    CrashReporting.breadcrumb(
                        "send: HTTP \(http.statusCode) on \(request.url?.path ?? "?"), retrying (attempt \(attempt))",
                        category: "network")
                    try await retrySleep(Self.backoffDelay(attempt: attempt, retryAfter: hint))
                    continue
                }
                return (data, http)
            } catch let error as URLError where canRetry && Self.isRetryable(error) {
                CrashReporting.breadcrumb(
                    "send: \(error.code.rawValue) on \(request.url?.path ?? "?"), retrying (attempt \(attempt))",
                    category: "network")
                try await retrySleep(Self.backoffDelay(attempt: attempt, retryAfter: nil))
                continue
            }
        }
    }

    // MARK: - Retry policy

    private static let retryableStatuses: Set<Int> = [429, 500, 502, 503, 504]

    private static let retryableURLErrorCodes: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost, .cannotConnectToHost,
        .cannotFindHost, .dnsLookupFailed, .secureConnectionFailed,
        .resourceUnavailable
    ]

    static func isRetryable(status: Int) -> Bool { retryableStatuses.contains(status) }

    static func isRetryable(_ error: URLError) -> Bool {
        retryableURLErrorCodes.contains(error.code)
    }

    /// Exponential backoff (base 0.6s, doubling, capped at 8s) plus up to 0.4s of
    /// jitter. A numeric `Retry-After` header wins, clamped to the same cap.
    static func backoffDelay(attempt: Int, retryAfter: String?) -> TimeInterval {
        let cap: TimeInterval = 8
        if let retryAfter, let seconds = TimeInterval(retryAfter.trimmingCharacters(in: .whitespaces)) {
            return min(max(0, seconds), cap)
        }
        let exponential = min(cap, 0.6 * pow(2, Double(max(0, attempt - 1))))
        return exponential + Double.random(in: 0...0.4)
    }

    /// Returns the Google OAuth URL from the backend
    func getGoogleAuthURL() -> URL? {
        return URL(string: "\(BACKEND_URL)auth/google")
    }

    /// Parse an OAuth callback URL (plannr://auth/callback?...). Handles both the
    /// success payload (email/name/picture) and the backend's error payload
    /// (error=...). Returns true only when authentication completed.
    ///
    /// This is the single entry point for the callback — used both by
    /// ASWebAuthenticationSession's completion handler and by `.onOpenURL`, both
    /// of which are delivered on the main thread, so state is set synchronously.
    @discardableResult
    func handleCallback(url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "auth", components.path == "/callback" else {
            return false
        }

        var email: String?
        var name: String?
        var picture: String?

        for item in components.queryItems ?? [] {
            switch item.name {
            case "error":
                let message = item.value ?? ""
                errorMessage = message.isEmpty ? "Sign-in failed. Please try again." : message
                isLoading = false
                return false
            case "email":   email = item.value
            case "name":    name = item.value
            case "picture": picture = item.value
            default:        break
            }
        }

        guard let email = email, !email.isEmpty else {
            errorMessage = "Could not get your email from Google. Please try again."
            isLoading = false
            return false
        }

        errorMessage = nil
        completeAuthentication(email: email, name: name, picture: picture)
        return true
    }

    /// Called when OAuth completes successfully via web
    func completeAuthentication(email: String, name: String?, picture: String? = nil) {
        // Save to UserDefaults
        UserDefaults.standard.set(email, forKey: "userEmail")
        if let name = name {
            UserDefaults.standard.set(name, forKey: "userName")
        }
        if let picture = picture, !picture.isEmpty {
            UserDefaults.standard.set(picture, forKey: "userPhotoURL")
        }

        DispatchQueue.main.async {
            self.userEmail = email
            self.userName = name
            if let picture = picture, !picture.isEmpty {
                self.userPhotoURL = picture
            }
            self.isAuthenticated = true
            self.isLoading = false
            CrashReporting.setUser(email: email)
            // Load this account's custom photo (migrating the legacy one on first
            // sign-in), not whatever the previous session left in memory.
            self.migrateLegacyPhotoIfNeeded()
            self.localPhotoData = self.loadLocalPhotoData()
        }
    }

    /// Sign in as guest — no data is persisted
    func signInAsGuest() {
        DispatchQueue.main.async {
            self.isGuest = true
            self.isAuthenticated = true
            self.userEmail = nil
            self.userName = "Guest"
            self.localPhotoData = self.loadLocalPhotoData()
            CrashReporting.setUser(email: nil)
        }
    }

    /// Sign out the user
    func signOut() {
        UserDefaults.standard.removeObject(forKey: "userEmail")
        UserDefaults.standard.removeObject(forKey: "userName")
        UserDefaults.standard.removeObject(forKey: "userPhotoURL")

        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.isGuest = false
            self.userEmail = nil
            self.userName = nil
            self.userPhotoURL = nil
            self.localPhotoData = nil
            CrashReporting.setUser(email: nil)
        }
    }

    // MARK: - Local profile photo override

    /// Per-identity so signing into a different account doesn't show the previous
    /// user's custom photo: `profile_photo_<account-token>.jpg` when signed in,
    /// `profile_photo_guest.jpg` for a guest.
    private var localPhotoFilename: String {
        if let email = userEmail, !isGuest {
            return "profile_photo_\(AccountScope.token(forEmail: email)).jpg"
        }
        return "profile_photo_guest.jpg"
    }

    private var localPhotoURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(localPhotoFilename)
    }

    private func loadLocalPhotoData() -> Data? {
        guard let url = localPhotoURL else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Move the old unscoped `profile_photo.jpg` to the current account's file the
    /// first time a signed-in session sees it.
    private func migrateLegacyPhotoIfNeeded() {
        guard userEmail != nil, !isGuest,
              let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fm = FileManager.default
        let legacy = dir.appendingPathComponent(Self.legacyPhotoFilename)
        let scoped = dir.appendingPathComponent(localPhotoFilename)
        if fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: scoped.path) {
            try? fm.moveItem(at: legacy, to: scoped)
        }
    }

    func setLocalProfilePhoto(_ data: Data) {
        guard let url = localPhotoURL else { return }
        try? data.write(to: url)
        DispatchQueue.main.async {
            self.localPhotoData = data
        }
    }

    func clearLocalProfilePhoto() {
        if let url = localPhotoURL {
            try? FileManager.default.removeItem(at: url)
        }
        DispatchQueue.main.async {
            self.localPhotoData = nil
        }
    }

    // MARK: - Account deletion

    private enum DeletionOutcome {
        case deleted
        case failed(String)
    }

    /// Delete the account on the backend, then wipe all local state.
    ///
    /// For a signed-in user, local state is wiped **only if the backend confirms
    /// the deletion**. The backend `DELETE /account` is idempotent, so if the
    /// response is lost to a timeout the deletion may still have committed — we
    /// retry once and, if that also can't get a response, probe `GET /me` to see
    /// whether the account's credentials are already gone before deciding.
    /// Guests have nothing server-side, so they always succeed. Returns false
    /// (with `errorMessage` set) on a confirmed failure; the caller should
    /// surface that and keep the account intact.
    func deleteAccount() async -> Bool {
        await MainActor.run { isDeletingAccount = true }

        if !isGuest {
            guard let email = userEmail,
                  let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let deleteURL = URL(string: "\(BACKEND_URL)account?email=\(encodedEmail)"),
                  let meURL = URL(string: "\(BACKEND_URL)me?email=\(encodedEmail)") else {
                await MainActor.run {
                    self.errorMessage = "Couldn't delete your account. Please try again."
                    self.isDeletingAccount = false
                }
                return false
            }

            if case .failed(let message) = await confirmAccountDeletion(deleteURL: deleteURL, meURL: meURL) {
                await MainActor.run {
                    self.errorMessage = message
                    self.isDeletingAccount = false
                }
                return false
            }
        }

        clearLocalProfilePhoto()
        signOut()

        await MainActor.run { isDeletingAccount = false }
        return true
    }

    private func confirmAccountDeletion(deleteURL: URL, meURL: URL) async -> DeletionOutcome {
        let offlineMessage = "Couldn't reach the server to delete your account. Check your connection and try again."

        for attempt in 1...2 {
            var request = URLRequest(url: deleteURL)
            request.httpMethod = "DELETE"
            request.timeoutInterval = attempt == 1 ? 45 : 30
            do {
                let (data, response) = try await httpDataProvider(request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(code) { return .deleted }
                // A definite non-success response from the server (e.g. a 500 DB
                // error): retrying the same request won't help — report it.
                let serverMessage = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                return .failed(serverMessage
                    ?? "Account deletion failed on the server (\(code)). Your data was not deleted — please try again.")
            } catch {
                if attempt == 2 {
                    // Neither DELETE got a response. The first attempt may still
                    // have committed server-side — check whether this account's
                    // stored credentials are gone before giving up.
                    return await probeAccountDeleted(meURL: meURL, fallbackFailure: offlineMessage)
                }
                // otherwise: fall through and retry once
            }
        }
        return .failed(offlineMessage)
    }

    /// `GET /me` returns 401 when there are no stored Google credentials for the
    /// email — i.e. the account was deleted. Any other outcome means we can't
    /// confirm the deletion, so keep local data.
    private func probeAccountDeleted(meURL: URL, fallbackFailure: String) async -> DeletionOutcome {
        var request = URLRequest(url: meURL)
        request.timeoutInterval = 20
        do {
            let (_, response) = try await httpDataProvider(request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 404 { return .deleted }
            return .failed("We couldn't confirm your account was deleted. Please check your connection and try again.")
        } catch {
            return .failed(fallbackFailure)
        }
    }
}
