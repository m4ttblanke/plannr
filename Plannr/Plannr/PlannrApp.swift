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
    @AppStorage("onboarding.hasSeen") private var hasSeenOnboarding = false

    init() {
        AppAppearance.configure()

        // UI tests decide the first-run state explicitly: -uiTestShowOnboarding
        // forces the walkthrough, -uiTestReset otherwise skips straight to sign-in.
        let args = CommandLine.arguments
        if args.contains("-uiTestShowOnboarding") {
            UserDefaults.standard.set(false, forKey: "onboarding.hasSeen")
        } else if args.contains("-uiTestReset") {
            UserDefaults.standard.set(true, forKey: "onboarding.hasSeen")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenOnboarding {
                    SignInView()
                        .environmentObject(authManager)
                } else {
                    OnboardingView { hasSeenOnboarding = true }
                }
            }
            .onOpenURL { url in
                // ASWebAuthenticationSession normally intercepts the plannr://
                // redirect itself; this path covers the app being cold-opened
                // from the callback URL. Both routes share one parser.
                authManager.handleCallback(url: url)
            }
        }
    }
}
