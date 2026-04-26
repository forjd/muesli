import Foundation

struct SecureStorageTests {
    static func run() throws {
        try testEncryptDecryptRoundTrip()
        try testFileEncryptionRoundTripThroughTemporaryFile()
    }

    private static func testEncryptDecryptRoundTrip() throws {
        let secureStorage = SecureStorage(keyProvider: FixedStorageKeyProvider())
        let plaintext = Data("private data".utf8)

        let encrypted = try secureStorage.encrypt(plaintext)
        let decrypted = try secureStorage.decrypt(encrypted)

        try expect(secureStorage.isEncrypted(encrypted), "Expected encrypted payload to include Muesli storage header")
        try expect(encrypted != plaintext, "Expected encrypted data to differ from plaintext")
        try expectEqual(decrypted, plaintext)
    }

    private static func testFileEncryptionRoundTripThroughTemporaryFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MuesliSecureStorageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let secureStorage = SecureStorage(keyProvider: FixedStorageKeyProvider())
        let url = directory.appending(path: "recording.wav")
        try Data("audio bytes".utf8).write(to: url)

        try secureStorage.encryptFile(at: url)
        let encryptedData = try Data(contentsOf: url)
        try expect(secureStorage.isEncrypted(encryptedData), "Expected recording file to be encrypted")

        let temporaryURL = try secureStorage.decryptedTemporaryFile(from: url)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        try expectEqual(try Data(contentsOf: temporaryURL), Data("audio bytes".utf8))
        try expect(temporaryURL != url, "Expected decrypted audio to be written to a temporary file")
    }
}
