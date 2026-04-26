import Foundation

enum MeetingNotesTemplate: String, CaseIterable, Identifiable {
    case standard
    case decisions
    case standup

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard:
            "Standard Notes"
        case .decisions:
            "Decisions"
        case .standup:
            "Standup"
        }
    }

    func markdown(for session: TranscriptSession) -> String {
        switch self {
        case .standard:
            return [
                "# Meeting Notes",
                "",
                "## Summary",
                "",
                "## Decisions",
                "",
                "## Action Items",
                "",
                "## Transcript",
                "",
                TranscriptExporter.exportTranscriptText(for: session)
            ].joined(separator: "\n")
        case .decisions:
            return [
                "# Decisions",
                "",
                "## Decisions Made",
                "",
                "## Open Questions",
                "",
                "## Supporting Transcript",
                "",
                TranscriptExporter.exportTranscriptText(for: session)
            ].joined(separator: "\n")
        case .standup:
            return [
                "# Standup Notes",
                "",
                "## Yesterday",
                "",
                "## Today",
                "",
                "## Blockers",
                "",
                "## Transcript",
                "",
                TranscriptExporter.exportTranscriptText(for: session)
            ].joined(separator: "\n")
        }
    }
}
