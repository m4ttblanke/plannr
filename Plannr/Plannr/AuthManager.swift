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
            // Per-account class stores written by real sign-ins.
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("savedClasses.") {
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

    /// Single choke point for authenticated backend requests. Any 401 response —
    /// from any endpoint — triggers the global session-expired sign-out. Callers
    /// still handle their own non-401 status codes, and should bail out early
    /// (without showing their own error UI) when `http.statusCode == 401`.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 401 {
            handleSessionExpired()
        }
        return (data, http)
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

    /// Delete the account on the backend, then wipe all local state.
    ///
    /// For a signed-in user, local state is wiped **only if the backend confirms
    /// the deletion** — otherwise the stored Google credentials would be left on
    /// the server while the app looks signed out. Guests have nothing
    /// server-side, so they always succeed. Returns false (with `errorMessage`
    /// set) if the backend call failed; the caller should surface that and keep
    /// the account intact.
    func deleteAccount() async -> Bool {
        await MainActor.run { isDeletingAccount = true }

        if !isGuest {
            guard let email = userEmail,
                  let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "\(BACKEND_URL)account?email=\(encodedEmail)") else {
                await MainActor.run {
                    self.errorMessage = "Couldn't delete your account. Please try again."
                    self.isDeletingAccount = false
                }
                return false
            }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    await MainActor.run {
                        self.errorMessage = "Account deletion failed on the server. Your data was not deleted — please try again."
                        self.isDeletingAccount = false
                    }
                    return false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Couldn't reach the server to delete your account. Check your connection and try again."
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
}
