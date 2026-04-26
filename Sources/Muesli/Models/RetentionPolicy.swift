import Foundation

struct RetentionPolicy: Hashable, Codable {
    var target: RetentionTarget
    var days: Int

    init(target: RetentionTarget = .off, days: Int = 30) {
        self.target = target
        self.days = Self.clampedDays(days)
    }

    var isEnabled: Bool {
        target != .off
    }

    var cutoffDate: Date? {
        cutoffDate(now: Date())
    }

    func cutoffDate(now: Date) -> Date? {
        guard isEnabled else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: now)
    }

    func isExpired(_ session: TranscriptSession, now: Date = Date()) -> Bool {
        guard let cutoffDate = cutoffDate(now: now) else { return false }
        return session.createdAt < cutoffDate
    }

    static func clampedDays(_ days: Int) -> Int {
        min(max(days, 1), 365)
    }
}

enum RetentionTarget: String, CaseIterable, Identifiable, Hashable, Codable {
    case off
    case recordings
    case transcripts
    case recordingsAndTranscripts

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:
            "Off"
        case .recordings:
            "Recordings only"
        case .transcripts:
            "Transcripts only"
        case .recordingsAndTranscripts:
            "Recordings and transcripts"
        }
    }

    var detail: String {
        switch self {
        case .off:
            "Keep saved recordings and transcripts until you delete them."
        case .recordings:
            "Delete expired audio files while keeping saved transcripts."
        case .transcripts:
            "Clear expired transcript text while keeping saved audio."
        case .recordingsAndTranscripts:
            "Delete expired sessions, audio files, transcripts, and chunk files."
        }
    }
}
