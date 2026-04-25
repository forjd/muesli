import Foundation

struct TranscriptSession: Identifiable, Hashable, Codable {
    let id: UUID
    let createdAt: Date
    let audioURL: URL
    var model: ParakeetModel
    var status: TranscriptStatus
    var transcript: String
    var liveTranscript: String
    var finalTranscript: String
    var segments: [TranscriptSegment]
    var benchmarks: [TranscriptionBenchmark]
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        audioURL: URL,
        model: ParakeetModel,
        status: TranscriptStatus = .recorded,
        transcript: String = "",
        liveTranscript: String = "",
        finalTranscript: String = "",
        segments: [TranscriptSegment] = [],
        benchmarks: [TranscriptionBenchmark] = [],
        errorMessage: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.audioURL = audioURL
        self.model = model
        self.status = status
        self.transcript = transcript
        self.liveTranscript = liveTranscript
        self.finalTranscript = finalTranscript
        self.segments = segments
        self.benchmarks = benchmarks
        self.errorMessage = errorMessage
    }

    var displayTranscript: String {
        if !finalTranscript.isEmpty {
            return finalTranscript
        }
        if !liveTranscript.isEmpty {
            return liveTranscript
        }
        return transcript
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case audioURL
        case model
        case status
        case transcript
        case liveTranscript
        case finalTranscript
        case segments
        case benchmarks
        case errorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        audioURL = try container.decode(URL.self, forKey: .audioURL)
        model = try container.decode(ParakeetModel.self, forKey: .model)
        status = try container.decode(TranscriptStatus.self, forKey: .status)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        liveTranscript = try container.decodeIfPresent(String.self, forKey: .liveTranscript) ?? transcript
        finalTranscript = try container.decodeIfPresent(String.self, forKey: .finalTranscript) ?? ""
        segments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .segments) ?? []
        benchmarks = try container.decodeIfPresent([TranscriptionBenchmark].self, forKey: .benchmarks) ?? []
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

struct TranscriptionBenchmark: Identifiable, Hashable, Codable {
    let id: UUID
    let model: ParakeetModel
    let duration: TimeInterval
    let transcriptLength: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        model: ParakeetModel,
        duration: TimeInterval,
        transcriptLength: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.model = model
        self.duration = duration
        self.transcriptLength = transcriptLength
        self.createdAt = createdAt
    }
}

struct TranscriptSegment: Identifiable, Hashable, Codable {
    let id: UUID
    let chunkIndex: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    var text: String
    var source: TranscriptSegmentSource

    init(
        id: UUID = UUID(),
        chunkIndex: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        source: TranscriptSegmentSource
    ) {
        self.id = id
        self.chunkIndex = chunkIndex
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.source = source
    }
}

enum TranscriptSegmentSource: String, Hashable, Codable {
    case live
    case final
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

enum ParakeetBackend: String, CaseIterable, Identifiable, Hashable, Codable {
    case fluidAudio
    case python

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fluidAudio:
            "FluidAudio"
        case .python:
            "Python NeMo"
        }
    }

    var detail: String {
        switch self {
        case .fluidAudio:
            "Native Core ML Parakeet backend"
        case .python:
            "Project-local Python worker fallback"
        }
    }
}
