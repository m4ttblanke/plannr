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

    private static let localPhotoFilename = "profile_photo.jpg"

    init() {
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
        self.localPhotoData = Self.loadLocalPhotoData()
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
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
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

    /// Returns the Google OAuth URL from the backend
    func getGoogleAuthURL() -> URL? {
        return URL(string: "\(BACKEND_URL)auth/google")
    }

    /// Handle the OAuth callback URL
    func handleCallback(url: URL) {
        // Parse the custom URL callback (e.g. plannr://auth/callback?email=...&name=...)
        // The backend includes the email and name as URL query parameters after successful auth
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }

        // Check if this is our auth callback
        if components.host == "auth" && components.path == "/callback" {
            // Extract parameters from the URL
            if let queryItems = components.queryItems {
                for item in queryItems {
                    if item.name == "email", let value = item.value {
                        self.userEmail = value
                    }
                    if item.name == "name", let value = item.value {
                        self.userName = value
                    }
                    if item.name == "picture", let value = item.value, !value.isEmpty {
                        self.userPhotoURL = value
                    }
                }
            }

            if userEmail != nil {
                // Save to UserDefaults
                UserDefaults.standard.set(userEmail, forKey: "userEmail")
                UserDefaults.standard.set(userName, forKey: "userName")
                UserDefaults.standard.set(userPhotoURL, forKey: "userPhotoURL")

                DispatchQueue.main.async {
                    self.isAuthenticated = true
                    self.isLoading = false
                }
            }
        }
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
        }
    }

    /// Sign in as guest — no data is persisted
    func signInAsGuest() {
        DispatchQueue.main.async {
            self.isGuest = true
            self.isAuthenticated = true
            self.userEmail = nil
            self.userName = "Guest"
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
        }
    }

    // MARK: - Local profile photo override

    private static var localPhotoURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(localPhotoFilename)
    }

    private static func loadLocalPhotoData() -> Data? {
        guard let url = localPhotoURL else { return nil }
        return try? Data(contentsOf: url)
    }

    func setLocalProfilePhoto(_ data: Data) {
        guard let url = Self.localPhotoURL else { return }
        try? data.write(to: url)
        DispatchQueue.main.async {
            self.localPhotoData = data
        }
    }

    func clearLocalProfilePhoto() {
        if let url = Self.localPhotoURL {
            try? FileManager.default.removeItem(at: url)
        }
        DispatchQueue.main.async {
            self.localPhotoData = nil
        }
    }

    // MARK: - Account deletion

    /// Delete the account on the backend, then wipe all local state. No-op (besides local wipe) for guests.
    func deleteAccount() async -> Bool {
        await MainActor.run { isDeletingAccount = true }

        if !isGuest, let email = userEmail,
           let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "\(BACKEND_URL)account?email=\(encodedEmail)") {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            _ = try? await URLSession.shared.data(for: request)
        }

        clearLocalProfilePhoto()
        signOut()

        await MainActor.run { isDeletingAccount = false }
        return true
    }
}
