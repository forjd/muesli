import Foundation

struct DictationFeedbackEvent: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var detail: String
    var kind: DictationFeedbackKind
    var createdAt = Date()
}

enum DictationFeedbackKind: String, Hashable {
    case recordingStarted
    case recordingStopped
    case transcribing
    case failed
    case pasted

    var systemImage: String {
        switch self {
        case .recordingStarted:
            "mic.fill"
        case .recordingStopped:
            "stop.fill"
        case .transcribing:
            "waveform"
        case .failed:
            "exclamationmark.triangle.fill"
        case .pasted:
            "text.insert"
        }
    }
}
