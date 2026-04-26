import Foundation

struct MeetingDiarizationEngine {
    var turnPauseThreshold: TimeInterval = 1.4
    var maxSpeakers = 2
    var nearestTurnThreshold: TimeInterval = 2.0

    func fallbackDiarizedSegments(from segments: [TranscriptSegment]) -> [TranscriptSegment] {
        let sortedSegments = segments.sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.chunkIndex < rhs.chunkIndex
            }
            return lhs.startTime < rhs.startTime
        }

        guard !sortedSegments.isEmpty else { return [] }

        var currentSpeakerIndex = 0
        var previousEndTime: TimeInterval?

        return sortedSegments.map { segment in
            var updated = segment
            if let previousEndTime, segment.startTime - previousEndTime >= turnPauseThreshold {
                currentSpeakerIndex = (currentSpeakerIndex + 1) % max(1, maxSpeakers)
            }
            updated.speakerLabel = Self.label(for: currentSpeakerIndex)
            previousEndTime = max(segment.endTime, previousEndTime ?? segment.endTime)
            return updated
        }
    }

    func assignSpeakerTurns(_ turns: [SpeakerTurn], to segments: [TranscriptSegment]) -> [TranscriptSegment] {
        let sortedTurns = turns.sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.speakerLabel < rhs.speakerLabel
            }
            return lhs.startTime < rhs.startTime
        }

        return segments.map { segment in
            var updated = segment
            updated.speakerLabel = bestSpeakerLabel(for: segment, turns: sortedTurns)
            return updated
        }
    }

    static func speakerFormattedTranscript(for session: TranscriptSession) -> String {
        let speakerSegments = session.segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs.startTime == rhs.startTime {
                    return lhs.chunkIndex < rhs.chunkIndex
                }
                return lhs.startTime < rhs.startTime
            }

        guard speakerSegments.contains(where: { $0.speakerLabel != nil }) else {
            return session.displayTranscript
        }

        var lines: [String] = []
        var activeSpeaker: String?
        var activeText: [String] = []

        func flushActiveSpeaker() {
            guard let activeSpeaker, !activeText.isEmpty else { return }
            lines.append("\(activeSpeaker): \(activeText.joined(separator: " "))")
        }

        for segment in speakerSegments {
            let speaker = segment.speakerLabel ?? "Speaker"
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if activeSpeaker == nil {
                activeSpeaker = speaker
            }

            if speaker != activeSpeaker {
                flushActiveSpeaker()
                activeSpeaker = speaker
                activeText = []
            }

            activeText.append(text)
        }

        flushActiveSpeaker()
        return lines.joined(separator: "\n\n")
    }

    static func speakerCount(in segments: [TranscriptSegment]) -> Int {
        Set(segments.compactMap(\.speakerLabel)).count
    }

    private static func label(for index: Int) -> String {
        "Speaker \(index + 1)"
    }

    private func bestSpeakerLabel(for segment: TranscriptSegment, turns: [SpeakerTurn]) -> String? {
        guard !turns.isEmpty else { return nil }

        let overlaps = turns.map { turn in
            (
                label: turn.speakerLabel,
                overlap: max(0, min(segment.endTime, turn.endTime) - max(segment.startTime, turn.startTime))
            )
        }
        if let bestOverlap = overlaps.max(by: { $0.overlap < $1.overlap }),
           bestOverlap.overlap > 0 {
            return bestOverlap.label
        }

        let midpoint = (segment.startTime + segment.endTime) / 2
        let nearest = turns
            .map { turn -> (label: String, distance: TimeInterval) in
                let clamped = min(max(midpoint, turn.startTime), turn.endTime)
                return (turn.speakerLabel, abs(midpoint - clamped))
            }
            .min { lhs, rhs in
                if lhs.distance == rhs.distance {
                    return lhs.label < rhs.label
                }
                return lhs.distance < rhs.distance
            }

        guard let nearest, nearest.distance <= nearestTurnThreshold else {
            return nil
        }
        return nearest.label
    }
}
