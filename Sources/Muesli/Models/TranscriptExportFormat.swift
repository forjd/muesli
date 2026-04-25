import UniformTypeIdentifiers

enum TranscriptExportFormat {
    case text
    case json
    case srt

    var fileExtension: String {
        switch self {
        case .text:
            "txt"
        case .json:
            "json"
        case .srt:
            "srt"
        }
    }

    var contentType: UTType {
        switch self {
        case .text:
            .plainText
        case .json:
            .json
        case .srt:
            UTType(filenameExtension: "srt") ?? .plainText
        }
    }
}
