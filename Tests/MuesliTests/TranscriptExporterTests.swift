import Foundation

struct TranscriptExporterTests {
    static func run() throws {
        try testTextExportUsesDisplayTranscript()
        try testMarkdownExportIncludesMetadataAndTranscript()
        try testClipboardNotesTemplateIncludesSections()
        try testDOCXExportCreatesZipPackage()
        try testSRTExportSortsSegmentsAndEnforcesMinimumDuration()
        try testSRTExportIncludesSpeakerLabels()
        try testMarkdownExportUsesSpeakerTranscriptForMeetings()
        try testTextExportIncludesSystemAudioTranscriptForMeetings()
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

    private static func testMarkdownExportIncludesMetadataAndTranscript() throws {
        let session = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 0),
            audioURL: URL(filePath: "/tmp/audio.wav"),
            model: .v3,
            transcript: "hello markdown",
            duration: 65
        )

        let text = String(decoding: try TranscriptExporter.data(for: session, format: .markdown), as: UTF8.self)

        try expect(text.contains("# Muesli Transcript"), "Missing Markdown heading")
        try expect(text.contains("- Model: Parakeet TDT 0.6B v3"), "Missing model metadata")
        try expect(text.contains("hello markdown"), "Missing transcript")
    }

    private static func testClipboardNotesTemplateIncludesSections() throws {
        let session = TranscriptSession(
            audioURL: URL(filePath: "/tmp/audio.wav"),
            model: .v3,
            transcript: "remember this"
        )

        let text = TranscriptExporter.clipboardText(for: session, template: .notes)

        try expect(text.contains("## Summary"), "Missing summary section")
        try expect(text.contains("## Transcript"), "Missing transcript section")
        try expect(text.contains("remember this"), "Missing transcript body")
    }

    private static func testDOCXExportCreatesZipPackage() throws {
        let session = TranscriptSession(
            audioURL: URL(filePath: "/tmp/audio.wav"),
            model: .v3,
            transcript: "docx body"
        )

        let data = try TranscriptExporter.data(for: session, format: .docx)

        try expect(data.count > 4, "DOCX package was empty")
        try expectEqual(Array(data.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
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

    private static func testSRTExportIncludesSpeakerLabels() throws {
        let session = TranscriptSession(
            audioURL: URL(filePath: "/tmp/audio.wav"),
            model: .v3,
            transcript: "fallback",
            segments: [
                TranscriptSegment(chunkIndex: 1, startTime: 1.0, endTime: 2.0, text: "hello", source: .live, speakerLabel: "Speaker 1")
            ],
            workflow: .meeting,
            meetingMetadata: MeetingMetadata(diarizationStatus: .complete, speakerCount: 2)
        )

        let text = TranscriptExporter.srtText(for: session)

        try expect(text.contains("Speaker 1: hello"), "Missing speaker label in SRT")
    }

    private static func testMarkdownExportUsesSpeakerTranscriptForMeetings() throws {
        let session = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 0),
            audioURL: URL(filePath: "/tmp/audio.wav"),
            model: .v3,
            transcript: "plain text",
            segments: [
                TranscriptSegment(chunkIndex: 1, startTime: 0.0, endTime: 1.0, text: "hello", source: .live, speakerLabel: "Speaker 1"),
                TranscriptSegment(chunkIndex: 2, startTime: 2.5, endTime: 3.0, text: "hi", source: .live, speakerLabel: "Speaker 2")
            ],
            workflow: .meeting,
            meetingMetadata: MeetingMetadata(diarizationStatus: .complete, speakerCount: 2)
        )

        let text = String(decoding: try TranscriptExporter.data(for: session, format: .markdown), as: UTF8.self)

        try expect(text.contains("- Workflow: Meeting"), "Missing workflow metadata")
        try expect(text.contains("- Speakers: 2"), "Missing speaker metadata")
        try expect(text.contains("Speaker 1: hello"), "Missing first speaker transcript")
        try expect(text.contains("Speaker 2: hi"), "Missing second speaker transcript")
    }

    private static func testTextExportIncludesSystemAudioTranscriptForMeetings() throws {
        let session = TranscriptSession(
            audioURL: URL(filePath: "/tmp/audio.wav"),
            model: .v3,
            transcript: "mic side",
            workflow: .meeting,
            systemAudioTranscript: "system side"
        )

        let text = String(decoding: try TranscriptExporter.data(for: session, format: .text), as: UTF8.self)

        try expect(text.contains("mic side"), "Missing mic transcript")
        try expect(text.contains("System audio transcript:"), "Missing system audio heading")
        try expect(text.contains("system side"), "Missing system transcript")
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
