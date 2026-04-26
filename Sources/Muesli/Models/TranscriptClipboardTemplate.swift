enum TranscriptClipboardTemplate: String, CaseIterable, Identifiable {
    case plain
    case markdown
    case notes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plain:
            "Plain Transcript"
        case .markdown:
            "Markdown"
        case .notes:
            "Notes Template"
        }
    }
}
