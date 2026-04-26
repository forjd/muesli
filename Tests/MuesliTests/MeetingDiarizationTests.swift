import Foundation

struct MeetingDiarizationTests {
    static func run() throws {
        try testFallbackDiarizationAlternatesSpeakersAcrossLongPauses()
        try testSpeakerTurnAssignmentUsesExactOverlap()
        try testSpeakerTurnAssignmentChoosesLargestOverlap()
        try testSpeakerTurnAssignmentUsesNearestTurnWithinThreshold()
        try testSpeakerTurnAssignmentLeavesSegmentUnlabeledWhenNoTurnIsClose()
        try testSpeakerFormattedTranscriptMergesAdjacentSegments()
        try testLegacySessionsDecodeAsDictation()
    }

    private static func testFallbackDiarizationAlternatesSpeakersAcrossLongPauses() throws {
        let segments = [
            TranscriptSegment(chunkIndex: 0, startTime: 0.0, endTime: 1.0, text: "first turn", source: .live),
            TranscriptSegment(chunkIndex: 1, startTime: 1.2, endTime: 2.0, text: "same turn", source: .live),
            TranscriptSegment(chunkIndex: 2, startTime: 4.0, endTime: 5.0, text: "second turn", source: .live)
        ]

        let diarized = MeetingDiarizationEngine().fallbackDiarizedSegments(from: segments)

        try expectEqual(diarized.map(\.speakerLabel), ["Speaker 1", "Speaker 1", "Speaker 2"])
    }

    private static func testSpeakerTurnAssignmentUsesExactOverlap() throws {
        let segment = TranscriptSegment(chunkIndex: 0, startTime: 2.0, endTime: 4.0, text: "hello", source: .live)
        let turns = [
            SpeakerTurn(speakerID: "a", speakerLabel: "Speaker 1", startTime: 1.0, endTime: 4.5, qualityScore: 0.9)
        ]

        let diarized = MeetingDiarizationEngine().assignSpeakerTurns(turns, to: [segment])

        try expectEqual(diarized.first?.speakerLabel, "Speaker 1")
    }

    private static func testSpeakerTurnAssignmentChoosesLargestOverlap() throws {
        let segment = TranscriptSegment(chunkIndex: 0, startTime: 5.0, endTime: 8.0, text: "mixed", source: .live)
        let turns = [
            SpeakerTurn(speakerID: "a", speakerLabel: "Speaker 1", startTime: 4.0, endTime: 5.5, qualityScore: 0.7),
            SpeakerTurn(speakerID: "b", speakerLabel: "Speaker 2", startTime: 5.6, endTime: 8.0, qualityScore: 0.8)
        ]

        let diarized = MeetingDiarizationEngine().assignSpeakerTurns(turns, to: [segment])

        try expectEqual(diarized.first?.speakerLabel, "Speaker 2")
    }

    private static func testSpeakerTurnAssignmentUsesNearestTurnWithinThreshold() throws {
        let segment = TranscriptSegment(chunkIndex: 0, startTime: 10.0, endTime: 11.0, text: "nearby", source: .live)
        let turns = [
            SpeakerTurn(speakerID: "a", speakerLabel: "Speaker 1", startTime: 8.6, endTime: 9.0, qualityScore: 0.9)
        ]

        let diarized = MeetingDiarizationEngine().assignSpeakerTurns(turns, to: [segment])

        try expectEqual(diarized.first?.speakerLabel, "Speaker 1")
    }

    private static func testSpeakerTurnAssignmentLeavesSegmentUnlabeledWhenNoTurnIsClose() throws {
        let segment = TranscriptSegment(chunkIndex: 0, startTime: 10.0, endTime: 11.0, text: "far", source: .live)
        let turns = [
            SpeakerTurn(speakerID: "a", speakerLabel: "Speaker 1", startTime: 1.0, endTime: 2.0, qualityScore: 0.9)
        ]

        let diarized = MeetingDiarizationEngine().assignSpeakerTurns(turns, to: [segment])

        try expect(diarized.first?.speakerLabel == nil, "Expected no speaker label for distant turn")
    }

    private static func testSpeakerFormattedTranscriptMergesAdjacentSegments() throws {
        let session = TranscriptSession(
            audioURL: URL(filePath: "/tmp/audio.wav"),
            model: .v3,
            transcript: "fallback",
            segments: [
                TranscriptSegment(chunkIndex: 0, startTime: 0.0, endTime: 1.0, text: "first", source: .live, speakerLabel: "Speaker 1"),
                TranscriptSegment(chunkIndex: 1, startTime: 1.1, endTime: 2.0, text: "continued", source: .live, speakerLabel: "Speaker 1"),
                TranscriptSegment(chunkIndex: 2, startTime: 4.0, endTime: 5.0, text: "reply", source: .live, speakerLabel: "Speaker 2")
            ],
            workflow: .meeting,
            meetingMetadata: MeetingMetadata(diarizationStatus: .complete, speakerCount: 2)
        )

        let text = MeetingDiarizationEngine.speakerFormattedTranscript(for: session)

        try expectEqual(text, "Speaker 1: first continued\n\nSpeaker 2: reply")
    }

    private static func testLegacySessionsDecodeAsDictation() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "createdAt": "1970-01-01T00:00:00Z",
          "audioURL": "file:///tmp/audio.wav",
          "model": "nvidia/parakeet-tdt-0.6b-v3",
          "status": "Complete",
          "transcript": "legacy",
          "segments": [],
          "isAudioEncrypted": false
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let session = try decoder.decode(TranscriptSession.self, from: Data(json.utf8))

        try expectEqual(session.workflow, .dictation)
        try expect(session.meetingMetadata == nil, "Expected legacy sessions to omit meeting metadata")
    }
}
