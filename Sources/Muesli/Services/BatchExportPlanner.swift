import Foundation

struct BatchExportPlanner {
    static func destinationURLs(
        for sessions: [TranscriptSession],
        format: TranscriptExportFormat,
        outputDirectory: URL
    ) -> [TranscriptSession.ID: URL] {
        var usedNames: [String: Int] = [:]
        var urls: [TranscriptSession.ID: URL] = [:]

        for session in sessions {
            let baseName = exportBaseName(for: session)
            let fileName: String
            if let count = usedNames[baseName] {
                usedNames[baseName] = count + 1
                fileName = "\(baseName)-\(count + 1).\(format.fileExtension)"
            } else {
                usedNames[baseName] = 1
                fileName = "\(baseName).\(format.fileExtension)"
            }
            urls[session.id] = outputDirectory.appending(path: fileName)
        }

        return urls
    }

    static func exportBaseName(for session: TranscriptSession) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return "muesli-\(formatter.string(from: session.createdAt))"
    }
}
