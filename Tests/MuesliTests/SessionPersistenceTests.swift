import Foundation

struct SessionPersistenceTests {
    static func run() throws {
        try testSaveAndLoadSessions()
        try testInterruptedSessionsLoadAsRecorded()
    }

    private static func testSaveAndLoadSessions() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = SessionPersistence(appSupportDirectory: directory)
        let session = TranscriptSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            createdAt: Date(timeIntervalSince1970: 1_234),
            audioURL: directory.appending(path: "sample.wav"),
            model: .v3,
            status: .complete,
            transcript: "hello world",
            duration: 2.5,
            fileSize: 512
        )

        try persistence.save([session])

        let loaded = persistence.load()
        try expectEqual(loaded, [session])
    }

    private static func testInterruptedSessionsLoadAsRecorded() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = SessionPersistence(appSupportDirectory: directory)
        let session = TranscriptSession(
            audioURL: directory.appending(path: "interrupted.wav"),
            model: .v2,
            status: .transcribing,
            transcript: "partial",
            errorMessage: "interrupted"
        )

        try persistence.save([session])

        guard let loaded = persistence.load().first else {
            throw TestFailure("Expected one loaded session")
        }
        try expectEqual(loaded.status, .recorded)
        try expect(loaded.errorMessage == nil, "Expected interrupted session error to be cleared")
        try expectEqual(loaded.transcript, "partial")
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MuesliTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
