import Foundation

struct TranscriptSession: Identifiable, Hashable, Codable {
    let id: UUID
    let createdAt: Date
    let audioURL: URL
    var model: ParakeetModel
    var status: TranscriptStatus
    var transcript: String
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        audioURL: URL,
        model: ParakeetModel,
        status: TranscriptStatus = .recorded,
        transcript: String = "",
        errorMessage: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.audioURL = audioURL
        self.model = model
        self.status = status
        self.transcript = transcript
        self.errorMessage = errorMessage
    }
}

enum TranscriptStatus: String, Hashable, Codable {
    case recording = "Recording"
    case recorded = "Recorded"
    case finalizing = "Finalizing"
    case transcribing = "Transcribing"
    case complete = "Complete"
    case failed = "Failed"
}

enum ParakeetModel: String, CaseIterable, Identifiable, Hashable, Codable {
    case v3 = "nvidia/parakeet-tdt-0.6b-v3"
    case v2 = "nvidia/parakeet-tdt-0.6b-v2"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .v3:
            "Parakeet TDT 0.6B v3"
        case .v2:
            "Parakeet TDT 0.6B v2"
        }
    }

    var detail: String {
        switch self {
        case .v3:
            "Multilingual, automatic language detection"
        case .v2:
            "English, strong leaderboard accuracy"
        }
    }
}
