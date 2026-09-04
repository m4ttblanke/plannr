//
//  BackendAuth.swift
//  Plannr
//
//  Per-user backend requests are authenticated with an opaque bearer token the
//  server issues at sign-in (delivered on the `plannr://auth/callback` redirect
//  and stored by AuthManager). Every request to a per-user endpoint — /me,
//  /calendar/sync, /calendar/meetings, /calendar/visibility, DELETE /calendar,
//  DELETE /account — must carry it as `Authorization: Bearer <token>`. The email
//  query parameter identifies the account; it is not a credential.
//

import Foundation

/// UserDefaults key holding the current session's backend bearer token.
let sessionTokenDefaultsKey = "sessionToken"

/// Attach the signed-in account's bearer token to `request`, if one is stored.
/// A no-op for guests / signed-out state — those callers never hit a per-user
/// endpoint, and the backend answers 401 if one somehow slips through.
func attachBackendAuth(_ request: inout URLRequest) {
    if let token = UserDefaults.standard.string(forKey: sessionTokenDefaultsKey), !token.isEmpty {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}
