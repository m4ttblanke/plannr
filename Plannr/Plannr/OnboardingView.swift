//
//  OnboardingView.swift
//  Plannr
//
//  First-run walkthrough: three cards (upload → review & edit → sync) shown once
//  before the sign-in screen. Dismissed by "Get Started" or "Skip"; the
//  `onboarding.hasSeen` flag then keeps it from coming back.
//

import SwiftUI

struct OnboardingPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let blurb: String
}

struct OnboardingView: View {
    /// Called when the user finishes or skips — the caller flips `hasSeenOnboarding`.
    var onFinish: () -> Void

    @State private var index = 0

    private let gold = Color(red: 1, green: 0.72, blue: 0.11)

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "arrow.up.doc.fill",
            title: "Upload your syllabus",
            blurb: "Drop in a PDF, scan a photo, or paste the text. Plannr reads the assignment and exam dates for you."
        ),
        OnboardingPage(
            icon: "checklist",
            title: "Review & edit",
            blurb: "Skim what Plannr found, fix any details, and choose which events to keep before anything is added."
        ),
        OnboardingPage(
            icon: "calendar.badge.checkmark",
            title: "Sync to Google Calendar",
            blurb: "One tap puts every event on a color-coded calendar for the class. Re-upload later and it stays in sync."
        )
    ]

    private var isLastPage: Bool { index == pages.count - 1 }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0, green: 0.2, blue: 0.4),
                    Color(red: 0, green: 0.15, blue: 0.35)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { onFinish() }
                        .font(.system(.subheadline, design: .serif).weight(.medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.trailing, 24)
                        .padding(.top, 12)
                        .opacity(isLastPage ? 0 : 1)
                        .disabled(isLastPage)
                        .accessibilityIdentifier("onboardingSkip")
                }

                TabView(selection: $index) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { position, page in
                        pageCard(page).tag(position)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: index)

                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { i in
                        Circle()
                            .fill(i == index ? Color.white : Color.white.opacity(0.35))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 24)

                Button(action: advance) {
                    Text(isLastPage ? "Get Started" : "Next")
                        .font(.system(.headline, design: .serif).weight(.bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(gold)
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
                .accessibilityIdentifier(isLastPage ? "onboardingGetStarted" : "onboardingNext")
            }

            BottomWave()
                .frame(height: 120)
                .offset(y: 30)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
        .navigationBarHidden(true)
    }

    private func pageCard(_ page: OnboardingPage) -> some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 132, height: 132)
                Image(systemName: page.icon)
                    .font(.system(size: 54, weight: .regular))
                    .foregroundColor(gold)
            }

            VStack(spacing: 14) {
                Text(page.title)
                    .font(.system(.title, design: .serif).weight(.bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(page.blurb)
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 40)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func advance() {
        if isLastPage {
            onFinish()
        } else {
            withAnimation(.easeInOut) { index += 1 }
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
