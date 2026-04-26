import UniformTypeIdentifiers

enum TranscriptExportFormat {
    case text
    case markdown
    case docx
    case json
    case srt

    var fileExtension: String {
        switch self {
        case .text:
            "txt"
        case .markdown:
            "md"
        case .docx:
            "docx"
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
        case .markdown:
            UTType(filenameExtension: "md") ?? .plainText
        case .docx:
            UTType(filenameExtension: "docx") ?? .data
        case .json:
            .json
        case .srt:
            UTType(filenameExtension: "srt") ?? .plainText
        }
    }
}
