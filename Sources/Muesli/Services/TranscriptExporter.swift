import Foundation

struct TranscriptExporter {
    static func data(for session: TranscriptSession, format: TranscriptExportFormat) throws -> Data {
        switch format {
        case .text:
            return Data(session.displayTranscript.utf8)
        case .json:
            let payload = TranscriptExportPayload(
                id: session.id,
                createdAt: session.createdAt,
                audioPath: session.audioURL.path,
                model: session.model.rawValue,
                transcript: session.displayTranscript,
                liveTranscript: session.liveTranscript,
                finalTranscript: session.finalTranscript,
                segments: session.segments,
                benchmarks: session.benchmarks,
                duration: session.duration,
                fileSize: session.fileSize
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(payload)
        case .srt:
            return Data(srtText(for: session).utf8)
        }
    }

    static func srtText(for session: TranscriptSession) -> String {
        let segments = session.segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.startTime < $1.startTime }

        if segments.isEmpty {
            return "1\n00:00:00,000 --> 00:00:05,000\n\(session.displayTranscript)\n"
        }

        return segments.enumerated().map { index, segment in
            [
                "\(index + 1)",
                "\(formatSRTTime(segment.startTime)) --> \(formatSRTTime(max(segment.endTime, segment.startTime + 1)))",
                segment.text,
                ""
            ].joined(separator: "\n")
        }.joined(separator: "\n")
    }

    static func formatSRTTime(_ time: TimeInterval) -> String {
        let milliseconds = Int((time * 1000).rounded())
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds % 3_600_000) / 60_000
        let seconds = (milliseconds % 60_000) / 1000
        let millis = milliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }
}

private struct TranscriptExportPayload: Encodable {
    let id: UUID
    let createdAt: Date
    let audioPath: String
    let model: String
    let transcript: String
    let liveTranscript: String
    let finalTranscript: String
    let segments: [TranscriptSegment]
    let benchmarks: [TranscriptionBenchmark]
    let duration: TimeInterval?
    let fileSize: Int64?
}
