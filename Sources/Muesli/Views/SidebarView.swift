import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        List(selection: $store.selectedSessionID) {
            Section("Recordings") {
                if store.sessions.isEmpty {
                    Text("No recordings")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.sessions) { session in
                        SidebarSessionRow(session: session)
                            .tag(session.id)
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
                    .lineLimit(1)

                Text(session.status.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var iconName: String {
        switch session.status {
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
        case .recorded, .transcribing:
            .secondary
        case .complete:
            .green
        case .failed:
            .orange
        }
    }
}
