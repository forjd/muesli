import Foundation

struct TranscriptSessionFilterTests {
    static func run() throws {
        try testSearchMatchesTranscriptAndFilename()
        try testStatusFilterGroupsActiveRecordedStates()
    }

    private static func testSearchMatchesTranscriptAndFilename() throws {
        let sessions = [
            TranscriptSession(audioURL: URL(filePath: "/tmp/alpha.wav"), model: .v3, transcript: "budget notes"),
            TranscriptSession(audioURL: URL(filePath: "/tmp/beta.wav"), model: .v3, transcript: "meeting")
        ]

        try expectEqual(TranscriptSessionFilter(searchText: "budget").apply(to: sessions).map(\.audioURL.lastPathComponent), ["alpha.wav"])
        try expectEqual(TranscriptSessionFilter(searchText: "beta").apply(to: sessions).map(\.audioURL.lastPathComponent), ["beta.wav"])
    }

    private static func testStatusFilterGroupsActiveRecordedStates() throws {
        let sessions = [
            TranscriptSession(audioURL: URL(filePath: "/tmp/recorded.wav"), model: .v3, status: .recorded),
            TranscriptSession(audioURL: URL(filePath: "/tmp/transcribing.wav"), model: .v3, status: .transcribing),
            TranscriptSession(audioURL: URL(filePath: "/tmp/done.wav"), model: .v3, status: .complete)
        ]

        let filtered = TranscriptSessionFilter(status: .recorded).apply(to: sessions)

        try expectEqual(filtered.map(\.audioURL.lastPathComponent), ["recorded.wav", "transcribing.wav"])
    }
}
