import Foundation

enum DictationStorageMode: String, CaseIterable, Identifiable, Hashable, Codable {
    case saveRecordingAndTranscript
    case saveTranscriptOnly
    case saveNothing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .saveRecordingAndTranscript:
            "Save recording and transcript"
        case .saveTranscriptOnly:
            "Never save audio"
        case .saveNothing:
            "Save nothing"
        }
    }

    var detail: String {
        switch self {
        case .saveRecordingAndTranscript:
            "Keep dictation recordings and transcripts in the history."
        case .saveTranscriptOnly:
            "Delete temporary dictation audio after transcription while keeping the transcript."
        case .saveNothing:
            "Delete temporary dictation audio and remove the transcript after paste or copy."
        }
    }

    var deletesAudio: Bool {
        self == .saveTranscriptOnly || self == .saveNothing
    }

    var keepsTranscript: Bool {
        self != .saveNothing
    }
}
