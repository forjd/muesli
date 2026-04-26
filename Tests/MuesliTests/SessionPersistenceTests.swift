import Foundation
import CryptoKit

struct SessionPersistenceTests {
    static func run() throws {
        try testSaveAndLoadSessions()
        try testSaveAndLoadMeetingSourceMetadata()
        try testInterruptedSessionsLoadAsRecorded()
        try testSaveEncryptsSessionMetadata()
        try testPlaintextSessionsAreMigratedToEncryptedStorage()
    }

    private static func testSaveAndLoadMeetingSourceMetadata() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = SessionPersistence(appSupportDirectory: directory, secureStorage: testSecureStorage())
        let session = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 4_000),
            audioURL: directory.appending(path: "mic.wav"),
            model: .v3,
            status: .complete,
            transcript: "meeting",
            isAudioEncrypted: true,
            workflow: .meeting,
            meetingMetadata: MeetingMetadata(diarizationStatus: .complete, speakerCount: 2, source: .microphoneAndSystemAudio),
            systemAudioURL: directory.appending(path: "system.m4a"),
            isSystemAudioEncrypted: true
        )

        try persistence.save([session])

        try expectEqual(persistence.load(), [session])
    }

    private static func testSaveAndLoadSessions() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let persistence = SessionPersistence(appSupportDirectory: directory, secureStorage: testSecureStorage())
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

        let persistence = SessionPersistence(appSupportDirectory: directory, secureStorage: testSecureStorage())
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

    private static func testSaveEncryptsSessionMetadata() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let secureStorage = testSecureStorage()
        let persistence = SessionPersistence(appSupportDirectory: directory, secureStorage: secureStorage)
        let session = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 2_000),
            audioURL: directory.appending(path: "private.wav"),
            model: .v3,
            status: .complete,
            transcript: "sensitive transcript"
        )

        try persistence.save([session])

        let storedData = try Data(contentsOf: persistence.sessionsURL)
        try expect(secureStorage.isEncrypted(storedData), "Expected sessions.json to be encrypted")
        try expect(!String(decoding: storedData, as: UTF8.self).contains("sensitive transcript"), "Expected transcript text not to appear in stored data")
        try expectEqual(persistence.load(), [session])
    }

    private static func testPlaintextSessionsAreMigratedToEncryptedStorage() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let secureStorage = testSecureStorage()
        let persistence = SessionPersistence(appSupportDirectory: directory, secureStorage: secureStorage)
        let session = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 3_000),
            audioURL: directory.appending(path: "legacy.wav"),
            model: .v2,
            status: .complete,
            transcript: "legacy transcript"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode([session]).write(to: persistence.sessionsURL, options: [.atomic])

        let loaded = persistence.load()
        let migratedData = try Data(contentsOf: persistence.sessionsURL)

        try expectEqual(loaded, [session])
        try expect(secureStorage.isEncrypted(migratedData), "Expected plaintext sessions.json to be migrated to encrypted storage")
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MuesliTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func testSecureStorage() -> SecureStorage {
        SecureStorage(keyProvider: FixedStorageKeyProvider())
    }
}

struct FixedStorageKeyProvider: SecureStorageKeyProvider {
    func storageKey() throws -> SymmetricKey {
        SymmetricKey(data: Data(repeating: 7, count: 32))
    }
}
