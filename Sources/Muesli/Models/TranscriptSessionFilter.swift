import Foundation

enum TranscriptStatusFilter: String, CaseIterable, Identifiable {
    case all
    case recorded
    case complete
    case failed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            "All"
        case .recorded:
            "Recorded"
        case .complete:
            "Complete"
        case .failed:
            "Failed"
        }
    }

    func matches(_ status: TranscriptStatus) -> Bool {
        switch self {
        case .all:
            true
        case .recorded:
            status == .recorded || status == .recording || status == .finalizing || status == .transcribing
        case .complete:
            status == .complete
        case .failed:
            status == .failed
        }
    }
}

struct TranscriptSessionFilter {
    var searchText: String = ""
    var status: TranscriptStatusFilter = .all

    func apply(to sessions: [TranscriptSession]) -> [TranscriptSession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return sessions.filter { session in
            guard status.matches(session.status) else { return false }
            guard !query.isEmpty else { return true }

            return searchableText(for: session)
                .localizedCaseInsensitiveContains(query)
        }
    }

    private func searchableText(for session: TranscriptSession) -> String {
        [
            session.audioURL.lastPathComponent,
            session.status.rawValue,
            session.model.label,
            session.displayTranscript,
            session.errorMessage ?? ""
        ].joined(separator: "\n")
    }
}
