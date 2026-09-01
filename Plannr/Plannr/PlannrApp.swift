//
//  PlannrApp.swift
//  Plannr
//
//  Created by Divya Subramonian on 1/21/26.
//

import SwiftUI

@main
struct PlannrApp: App {
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            SignInView()
                .environmentObject(authManager)
                .onOpenURL { url in
                    // ASWebAuthenticationSession normally intercepts the plannr://
                    // redirect itself; this path covers the app being cold-opened
                    // from the callback URL. Both routes share one parser.
                    authManager.handleCallback(url: url)
                }
        }
    }
}
