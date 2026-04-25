import Foundation

struct SessionPersistence {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Muesli", directoryHint: .isDirectory)
    }

    func load() -> [TranscriptSession] {
        guard let data = try? Data(contentsOf: sessionsURL) else {
            return []
        }

        do {
            return try decoder.decode([TranscriptSession].self, from: data).map { session in
                var session = session
                if session.status == .transcribing || session.status == .recording || session.status == .finalizing {
                    session.status = .recorded
                    session.errorMessage = nil
                }
                return session
            }
        } catch {
            return []
        }
    }

    func save(_ sessions: [TranscriptSession]) throws {
        try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(sessions)
        try data.write(to: sessionsURL, options: [.atomic])
    }
}
