//
//  ParsePhase.swift
//  Plannr
//
//  The syllabus-parse pipeline gives no progress signal — a single POST that
//  can take 30s+ on a cold Render start. These are time-based estimates so the
//  wait shows plausible forward motion ("Waking the server…" → "Reading your
//  syllabus…" → "Extracting events…") instead of one indefinite spinner.
//

import SwiftUI

enum ParsePhase: CaseIterable {
    case wakingServer
    case reading
    case extracting

    var message: String {
        switch self {
        case .wakingServer: return "Waking the server…"
        case .reading:      return "Reading your syllabus…"
        case .extracting:   return "Extracting events…"
        }
    }

    /// Seconds into the wait at which this phase begins.
    var startsAt: TimeInterval {
        switch self {
        case .wakingServer: return 0
        case .reading:      return 6
        case .extracting:   return 15
        }
    }

    /// Same thresholds compressed into a few seconds — used by the sample
    /// walkthrough, whose parse is faked but should still look phased.
    var startsAtAccelerated: TimeInterval {
        switch self {
        case .wakingServer: return 0
        case .reading:      return 1.6
        case .extracting:   return 3.2
        }
    }

    func threshold(accelerated: Bool) -> TimeInterval {
        accelerated ? startsAtAccelerated : startsAt
    }

    /// The phase to show after `elapsed` seconds. The final phase is sticky —
    /// a longer-than-expected wait keeps saying "Extracting events…" rather
    /// than cycling or claiming to be done.
    static func phase(forElapsed elapsed: TimeInterval, accelerated: Bool = false) -> ParsePhase {
        allCases.last { elapsed >= $0.threshold(accelerated: accelerated) } ?? .wakingServer
    }
}

/// Phased spinner shown while a syllabus uploads. Advances on a 1s tick from
/// `startedAt`; the caller shows it only while the request is in flight. The
/// sample walkthrough passes `accelerated` so the (fake) parse still shows all
/// three phases in a few seconds.
struct ParseProgressView: View {
    let startedAt: Date
    var accelerated: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: accelerated ? 0.4 : 1)) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let phase = ParsePhase.phase(forElapsed: elapsed, accelerated: accelerated)
            VStack(spacing: 10) {
                ProgressView()
                    .tint(.pink)

                Text(phase.message)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: phase)

                HStack(spacing: 6) {
                    ForEach(ParsePhase.allCases, id: \.self) { step in
                        Circle()
                            .fill(elapsed >= step.threshold(accelerated: accelerated) ? Color.pink : Color.gray.opacity(0.4))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityHidden(true)

                if !accelerated {
                    Text("The first upload after a while can take up to a minute while the server wakes up.")
                        .font(.caption2)
                        .foregroundColor(.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(phase.message)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
