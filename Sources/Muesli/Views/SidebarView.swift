import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        List(selection: $store.selectedSessionID) {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Search transcripts", text: $store.sessionSearchText)
                        .textFieldStyle(.roundedBorder)

                    Picker("Status", selection: $store.sessionStatusFilter) {
                        ForEach(TranscriptStatusFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 4)
            }

            Section("Recordings") {
                if store.sessions.isEmpty {
                    ContentUnavailableView {
                        Label("No Recordings", systemImage: "waveform")
                    } description: {
                        Text("Recorded clips will appear here.")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
                } else if store.filteredSessions.isEmpty {
                    ContentUnavailableView {
                        Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Adjust search or filter.")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
                } else {
                    ForEach(store.filteredSessions) { session in
                        SidebarSessionRow(session: session)
                            .tag(session.id)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    store.deleteSession(sessionID: session.id)
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarSessionRow: View {
    let session: TranscriptSession

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.createdAt, format: .dateTime.hour().minute().second())
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var detailText: String {
        let transcript = session.displayTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            return session.status.rawValue
        }

        return "\(session.status.rawValue) · \(transcript)"
    }

    private var iconName: String {
        switch session.status {
        case .recording:
            "mic.fill"
        case .finalizing:
            "hourglass"
        case .recorded:
            "waveform"
        case .transcribing:
            "arrow.triangle.2.circlepath"
        case .complete:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch session.status {
        case .recording:
            .red
        case .finalizing:
            .blue
        case .recorded, .transcribing:
            .secondary
        case .complete:
            .green
        case .failed:
            .orange
        }
    }
}
