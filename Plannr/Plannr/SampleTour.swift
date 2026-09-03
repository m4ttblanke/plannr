//
//  SampleTour.swift
//  Plannr
//
//  Drives the "Try a sample syllabus" guided walkthrough: a throwaway class is
//  created, parsed (simulated — no Gemini), previewed, "synced" (simulated — no
//  Google Calendar), and edited, with an anchored coach-mark bubble on each
//  step. When the tour ends the sample class is deleted, leaving no trace.
//

import SwiftUI

/// One stop on the tour, in order. The upload / preview / edit screens each
/// register anchors (`coachAnchor`) for the steps that belong to them.
enum CoachStep: Int, CaseIterable, Comparable {
    case uploadIntro
    case previewList
    case previewGrid
    case previewSync
    case editIntro
    case editDone

    static func < (a: CoachStep, b: CoachStep) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .uploadIntro: return "Start with a syllabus"
        case .previewList: return "Review what Plannr found"
        case .previewGrid: return "See the whole term"
        case .previewSync: return "Add it to your calendar"
        case .editIntro:   return "Adjust anytime"
        case .editDone:    return "That's the whole loop"
        }
    }

    var message: String {
        switch self {
        case .uploadIntro:
            return "We've loaded an example syllabus. Normally you'd drop in a PDF, scan a page, or paste text. Tap Got it and Plannr will read it."
        case .previewList:
            return "Every date from the syllabus is here, auto-accepted. Tap ✕ to drop one, or tap a card to fix its title, date, or type."
        case .previewGrid:
            return "The grid lays out the term at a glance, color-coded by class."
        case .previewSync:
            return "One tap normally pushes everything to a Google Calendar for the class. The sample won't touch your real calendar — tap Run it to see how it goes."
        case .editIntro:
            return "Here's the class afterwards. Open an event to edit it, or delete one you don't need — with a real class those changes re-sync on their own."
        case .editDone:
            return "Upload → review → sync → adjust. We'll clear the sample now so you can start with your own syllabus."
        }
    }

    var actionLabel: String {
        switch self {
        case .previewSync: return "Run it"
        case .editDone:    return "Finish"
        default:           return "Got it"
        }
    }
}

@MainActor
final class SampleTour: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var step: CoachStep?

    private(set) var sampleClassID: UUID?

    /// PDFUploadView sets this to tear the sample class down and pop navigation.
    var onFinish: ((UUID) -> Void)?

    func start(classID: UUID) {
        sampleClassID = classID
        isActive = true
        withAnimation { step = .uploadIntro }
    }

    /// Advance to the next step (or finish after the last one).
    func advance() {
        guard let current = step else { return }
        if let next = CoachStep(rawValue: current.rawValue + 1) {
            withAnimation { step = next }
        } else {
            finish()
        }
    }

    /// Jump to a specific step after a screen transition (parse finished, the
    /// simulated sync moved us to the edit screen, …).
    func enter(_ target: CoachStep) {
        guard isActive else { return }
        withAnimation { step = target }
    }

    func skip() { finish() }

    private func finish() {
        let id = sampleClassID
        isActive = false
        withAnimation { step = nil }
        sampleClassID = nil
        if let id { onFinish?(id) }
    }
}

// MARK: - Anchored coach marks

/// Screens publish the frame of a control for a given step via `coachAnchor`;
/// `coachMarks` reads them and draws the bubble for the current step.
struct CoachAnchorKey: PreferenceKey {
    static let defaultValue: [CoachStep: Anchor<CGRect>] = [:]
    static func reduce(value: inout [CoachStep: Anchor<CGRect>],
                       nextValue: () -> [CoachStep: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Mark this view as the target for `step`'s coach mark.
    func coachAnchor(_ step: CoachStep) -> some View {
        anchorPreference(key: CoachAnchorKey.self, value: .bounds) { [step: $0] }
    }

    /// Attach once at a screen's root. Shows the bubble for `tour.step` when a
    /// matching anchor exists on this screen. `onAcknowledge` defaults to
    /// advancing the tour; a screen can override it to run a transition first.
    func coachMarks(_ tour: SampleTour,
                    onAcknowledge: ((CoachStep) -> Void)? = nil) -> some View {
        overlayPreferenceValue(CoachAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if tour.isActive, let step = tour.step, let anchor = anchors[step] {
                    CoachMarkView(
                        step: step,
                        targetRect: proxy[anchor],
                        container: proxy.size,
                        onAcknowledge: { onAcknowledge?(step) ?? tour.advance() },
                        onSkip: { tour.skip() }
                    )
                }
            }
            .ignoresSafeArea()
        }
    }
}

struct CoachMarkView: View {
    let step: CoachStep
    let targetRect: CGRect
    let container: CGSize
    let onAcknowledge: () -> Void
    let onSkip: () -> Void

    private let bubbleWidth: CGFloat = 300
    private let estimatedHeight: CGFloat = 168
    private let gap: CGFloat = 14

    private var placeBelow: Bool {
        targetRect.maxY + gap + estimatedHeight < container.height - 24
    }

    private var bubbleX: CGFloat {
        min(max(targetRect.midX - bubbleWidth / 2, 12), container.width - 12 - bubbleWidth)
    }

    private var bubbleY: CGFloat {
        placeBelow ? targetRect.maxY + gap : max(targetRect.minY - gap - estimatedHeight, 24)
    }

    private var pointerX: CGFloat {
        min(max(targetRect.midX, bubbleX + 22), bubbleX + bubbleWidth - 22)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { }   // swallow taps; acknowledge is button-only
                .accessibilityHidden(true)

            // Highlight ring around the target.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(red: 1, green: 0.72, blue: 0.11), lineWidth: 2)
                .frame(width: targetRect.width + 12, height: targetRect.height + 12)
                .position(x: targetRect.midX, y: targetRect.midY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // Pointer triangle.
            Triangle()
                .fill(Color(white: 0.15))
                .frame(width: 18, height: 9)
                .rotationEffect(.degrees(placeBelow ? 0 : 180))
                .position(x: pointerX,
                          y: placeBelow ? bubbleY - 4 : bubbleY + estimatedHeight + 4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(step.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                Text(step.message)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Skip tour", action: onSkip)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Button(action: onAcknowledge) {
                        Text(step.actionLabel)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color(red: 1, green: 0.72, blue: 0.11))
                            .cornerRadius(9)
                    }
                }
                .padding(.top, 2)
            }
            .padding(14)
            .frame(width: bubbleWidth, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.15)))
            .position(x: bubbleX + bubbleWidth / 2, y: bubbleY + estimatedHeight / 2)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
