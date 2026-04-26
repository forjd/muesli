import Foundation

enum PrivacyMode: String, CaseIterable, Identifiable, Hashable, Codable {
    case localOnlyDictation = "localOnlyDictation"
    case localAIPostProcessing = "localAIPostProcessing"
    case remotePostProcessing = "remotePostProcessing"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .localOnlyDictation:
            "Local-only dictation"
        case .localAIPostProcessing:
            "Local AI post-processing"
        case .remotePostProcessing:
            "Remote post-processing"
        }
    }

    var shortLabel: String {
        switch self {
        case .localOnlyDictation:
            "Local-only"
        case .localAIPostProcessing:
            "Local AI"
        case .remotePostProcessing:
            "Remote"
        }
    }

    var detail: String {
        switch self {
        case .localOnlyDictation:
            "Audio and transcripts stay on this Mac. Network access is only used to download model files before local transcription."
        case .localAIPostProcessing:
            "Audio and transcripts stay on this Mac while a local provider rewrites, formats, or summarizes transcripts."
        case .remotePostProcessing:
            "Transcript text may be sent to the selected remote provider for rewriting, formatting, or summarization."
        }
    }

    var contentLeavesDevice: Bool {
        switch self {
        case .localOnlyDictation, .localAIPostProcessing:
            false
        case .remotePostProcessing:
            true
        }
    }

    var networkUse: String {
        switch self {
        case .localOnlyDictation:
            "Model downloads only"
        case .localAIPostProcessing:
            "Model downloads and local provider connections only"
        case .remotePostProcessing:
            "Remote provider requests"
        }
    }
}
