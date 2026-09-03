import SwiftUI

struct SyncSessionsView: View {
    let sessions: [SyncSession]
    /// The class's events right now — used to tell which session is the current
    /// one (its "Restore" button is disabled).
    var currentEvents: [CalendarEvent] = []
    /// Invoked (after the user confirms) to roll the class back to a session.
    var onRestore: ((SyncSession) -> Void)? = nil

    private var sortedSessions: [SyncSession] {
        sessions.sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if sessions.isEmpty {
                Text("No sync sessions yet.")
                    .foregroundColor(.secondaryText)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(sortedSessions.enumerated()), id: \.element.id) { index, session in
                            SessionRow(
                                sessionNumber: sortedSessions.count - index,
                                session: session,
                                isCurrentVersion: ClassRestore.isNoOp(snapshot: session.events, current: currentEvents),
                                onRestore: onRestore == nil ? nil : { onRestore?(session) }
                            )
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Sync Sessions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - SessionRow

struct SessionRow: View {
    let sessionNumber: Int
    let session: SyncSession
    var isCurrentVersion = false
    var onRestore: (() -> Void)? = nil

    @State private var isExpanded = false
    @State private var showRestoreConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — tap to expand/collapse
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session \(sessionNumber)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text(session.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondaryText)
                    }

                    Spacer()

                    Text("\(session.events.count) events")
                        .font(.caption)
                        .foregroundColor(.secondaryText)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                        .padding(.leading, 6)
                }
                .padding()
            }

            // Expandable event list
            if isExpanded {
                Divider()
                    .background(Color.gray.opacity(0.3))

                VStack(spacing: 10) {
                    ForEach(session.events) { event in
                        SyncEventRow(event: event)
                    }

                    if let onRestore {
                        Button {
                            showRestoreConfirm = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.uturn.backward")
                                Text(isCurrentVersion ? "Current version" : "Restore this version")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(isCurrentVersion ? .gray : .blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background((isCurrentVersion ? Color.gray : Color.blue).opacity(0.15))
                            .cornerRadius(8)
                        }
                        .disabled(isCurrentVersion)
                        .padding(.top, 4)
                        .confirmationDialog(
                            "Restore to Session \(sessionNumber)?",
                            isPresented: $showRestoreConfirm,
                            titleVisibility: .visible
                        ) {
                            Button("Restore \(session.events.count) event\(session.events.count == 1 ? "" : "s")", role: .destructive) {
                                onRestore()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Replaces this class's current events with the \(session.events.count) from \(session.date.formatted(date: .abbreviated, time: .shortened)) and updates Google Calendar. Any unsynced changes are lost.")
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color.gray.opacity(0.12))
        .cornerRadius(10)
    }
}

// MARK: - SyncEventRow (read-only, matches ClassEventRow style)

struct SyncEventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.blue)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Spacer()

                    Text(event.type.capitalized)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.3))
                        .cornerRadius(6)
                }

                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundColor(.secondaryText)
                    Text(event.date)
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                }

                if !event.description.isEmpty {
                    Text(event.description)
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                        .lineLimit(2)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.12))
        .cornerRadius(10)
    }
}
