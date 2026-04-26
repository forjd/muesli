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
    var duration: TimeInterval?
    var fileSize: Int64?
    var errorMessage: String?
    var isAudioEncrypted: Bool
    var workflow: TranscriptWorkflow
    var meetingMetadata: MeetingMetadata?

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
        duration: TimeInterval? = nil,
        fileSize: Int64? = nil,
        errorMessage: String? = nil,
        isAudioEncrypted: Bool = false,
        workflow: TranscriptWorkflow = .dictation,
        meetingMetadata: MeetingMetadata? = nil
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
        self.duration = duration
        self.fileSize = fileSize
        self.errorMessage = errorMessage
        self.isAudioEncrypted = isAudioEncrypted
        self.workflow = workflow
        self.meetingMetadata = meetingMetadata
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
        case duration
        case fileSize
        case errorMessage
        case isAudioEncrypted
        case workflow
        case meetingMetadata
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
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        isAudioEncrypted = try container.decodeIfPresent(Bool.self, forKey: .isAudioEncrypted) ?? false
        workflow = try container.decodeIfPresent(TranscriptWorkflow.self, forKey: .workflow) ?? .dictation
        meetingMetadata = try container.decodeIfPresent(MeetingMetadata.self, forKey: .meetingMetadata)
    }
}

enum TranscriptWorkflow: String, CaseIterable, Identifiable, Hashable, Codable {
    case dictation
    case meeting

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dictation:
            "Dictation"
        case .meeting:
            "Meeting"
        }
    }
}

struct MeetingMetadata: Hashable, Codable {
    var diarizationStatus: DiarizationStatus
    var speakerCount: Int
    var source: MeetingSource

    init(
        diarizationStatus: DiarizationStatus = .notStarted,
        speakerCount: Int = 0,
        source: MeetingSource = .microphone
    ) {
        self.diarizationStatus = diarizationStatus
        self.speakerCount = speakerCount
        self.source = source
    }
}

enum MeetingSource: String, Hashable, Codable {
    case microphone
    case importedAudio
    case microphoneAndSystemAudio
}

enum DiarizationStatus: String, Hashable, Codable {
    case notStarted
    case unavailable
    case complete
}

struct TranscriptSegment: Identifiable, Hashable, Codable {
    let id: UUID
    let chunkIndex: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    var text: String
    var source: TranscriptSegmentSource
    var speakerLabel: String?

    init(
        id: UUID = UUID(),
        chunkIndex: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        source: TranscriptSegmentSource,
        speakerLabel: String? = nil
    ) {
        self.id = id
        self.chunkIndex = chunkIndex
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.source = source
        self.speakerLabel = speakerLabel
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
