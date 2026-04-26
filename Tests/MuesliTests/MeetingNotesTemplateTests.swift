import Foundation

struct MeetingNotesTemplateTests {
    static func run() throws {
        try testStandardTemplateIncludesSpeakerAndSystemTranscripts()
        try testEveryTemplateHasTranscriptSection()
        try testPDFWriterProducesPDFData()
    }

    private static func testStandardTemplateIncludesSpeakerAndSystemTranscripts() throws {
        let session = TranscriptSession(
            audioURL: URL(filePath: "/tmp/mic.wav"),
            model: .v3,
            transcript: "fallback",
            segments: [
                TranscriptSegment(chunkIndex: 0, startTime: 0, endTime: 1, text: "hello", source: .live, speakerLabel: "Speaker 1")
            ],
            workflow: .meeting,
            meetingMetadata: MeetingMetadata(diarizationStatus: .complete, speakerCount: 1),
            systemAudioTranscript: "system side"
        )

        let markdown = MeetingNotesTemplate.standard.markdown(for: session)

        try expect(markdown.contains("## Summary"), "Missing summary section")
        try expect(markdown.contains("Speaker 1: hello"), "Missing speaker transcript")
        try expect(markdown.contains("System audio transcript:"), "Missing system audio transcript heading")
        try expect(markdown.contains("system side"), "Missing system audio transcript")
    }

    private static func testEveryTemplateHasTranscriptSection() throws {
        let session = TranscriptSession(
            audioURL: URL(filePath: "/tmp/mic.wav"),
            model: .v3,
            transcript: "body",
            workflow: .meeting
        )

        for template in MeetingNotesTemplate.allCases {
            try expect(template.markdown(for: session).contains("body"), "Missing transcript body for \(template.label)")
        }
    }

    private static func testPDFWriterProducesPDFData() throws {
        let data = MeetingNotesPDFWriter.data(title: "Meeting Notes", markdown: "# Meeting Notes\n\nBody")
        try expect(data.starts(with: Data("%PDF".utf8)), "Meeting notes PDF writer did not produce PDF data")
    }
}
