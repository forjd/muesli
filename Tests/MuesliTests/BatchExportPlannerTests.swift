import Foundation

struct BatchExportPlannerTests {
    static func run() throws {
        try testDestinationURLsAreStableAndUnique()
    }

    private static func testDestinationURLsAreStableAndUnique() throws {
        let date = Date(timeIntervalSince1970: 100)
        let sessions = [
            TranscriptSession(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, createdAt: date, audioURL: URL(filePath: "/tmp/one.wav"), model: .v3),
            TranscriptSession(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, createdAt: date, audioURL: URL(filePath: "/tmp/two.wav"), model: .v3)
        ]

        let urls = BatchExportPlanner.destinationURLs(for: sessions, format: .markdown, outputDirectory: URL(filePath: "/tmp/out"))

        try expectEqual(urls[sessions[0].id]?.lastPathComponent, "muesli-19700101-000140.md")
        try expectEqual(urls[sessions[1].id]?.lastPathComponent, "muesli-19700101-000140-2.md")
    }
}
