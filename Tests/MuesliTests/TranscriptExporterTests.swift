import Foundation

struct TranscriptExporterTests {
    static func run() throws {
        try testTextExportUsesDisplayTranscript()
        try testSRTExportSortsSegmentsAndEnforcesMinimumDuration()
        try testSRTExportFallsBackWhenNoSegmentsExist()
    }

    private static func testTextExportUsesDisplayTranscript() throws {
        let session = TranscriptSession(
            audioURL: URL(filePath: "/tmp/audio.wav"),
            model: .v3,
            transcript: "draft",
            liveTranscript: "live",
            finalTranscript: "final"
        )

        let data = try TranscriptExporter.data(for: session, format: .text)

        try expectEqual(String(decoding: data, as: UTF8.self), "final")
    }

    private static func testSRTExportSortsSegmentsAndEnforcesMinimumDuration() throws {
        let session = TranscriptSession(
            audioURL: URL(filePath: "/tmp/audio.wav"),
            model: .v3,
            transcript: "fallback",
            segments: [
                TranscriptSegment(chunkIndex: 2, startTime: 3.0, endTime: 3.2, text: "second", source: .final),
                TranscriptSegment(chunkIndex: 1, startTime: 1.0, endTime: 1.5, text: "first", source: .final)
            ]
        )

        let text = TranscriptExporter.srtText(for: session)

        try expect(text.contains("1\n00:00:01,000 --> 00:00:02,000\nfirst"), "Missing sorted first segment")
        try expect(text.contains("2\n00:00:03,000 --> 00:00:04,000\nsecond"), "Missing sorted second segment")
    }

    private static func testSRTExportFallsBackWhenNoSegmentsExist() throws {
        let session = TranscriptSession(
            audioURL: URL(filePath: "/tmp/audio.wav"),
            model: .v3,
            transcript: "plain transcript"
        )

        try expectEqual(
            TranscriptExporter.srtText(for: session),
            "1\n00:00:00,000 --> 00:00:05,000\nplain transcript\n"
        )
    }
}
