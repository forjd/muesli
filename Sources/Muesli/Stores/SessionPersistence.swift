import Foundation

struct SessionPersistence {
    private let fileManager: FileManager
    private let appSupportDirectoryOverride: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let secureStorage: SecureStorage

    init(
        fileManager: FileManager = .default,
        appSupportDirectory: URL? = nil,
        secureStorage: SecureStorage = SecureStorage()
    ) {
        self.fileManager = fileManager
        self.appSupportDirectoryOverride = appSupportDirectory
        self.secureStorage = secureStorage
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    var sessionsURL: URL {
        appSupportDirectory.appending(path: "sessions.json")
    }

    var appSupportDirectory: URL {
        if let appSupportDirectoryOverride {
            return appSupportDirectoryOverride
        }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Muesli", directoryHint: .isDirectory)
    }

    var recordingsDirectory: URL {
        appSupportDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
    }

    func load() -> [TranscriptSession] {
        guard let storedData = try? Data(contentsOf: sessionsURL) else {
            return []
        }

        do {
            let wasPlaintext = !secureStorage.isEncrypted(storedData)
            let data = try secureStorage.decrypt(storedData)
            let sessions = try decoder.decode([TranscriptSession].self, from: data).map { session in
                var session = session
                if session.status == .transcribing || session.status == .recording || session.status == .finalizing {
                    session.status = .recorded
                    session.errorMessage = nil
                }
                return session
            }

            if wasPlaintext {
                try? save(sessions)
            }

            return sessions
        } catch {
            return []
        }
    }

    func save(_ sessions: [TranscriptSession]) throws {
        try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(sessions)
        try secureStorage.encrypt(data).write(to: sessionsURL, options: [.atomic])
    }
}
