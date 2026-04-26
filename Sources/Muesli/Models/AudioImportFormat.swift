import UniformTypeIdentifiers

enum AudioImportFormat: String, CaseIterable {
    case wav
    case m4a
    case mp3
    case aiff
    case caf

    static var contentTypes: [UTType] {
        let explicitTypes = allCases.compactMap { UTType(filenameExtension: $0.rawValue) }
        return Array(Set([.audio] + explicitTypes))
    }

    static func isSupported(_ url: URL) -> Bool {
        allCases.contains { $0.rawValue == url.pathExtension.lowercased() }
    }
}
