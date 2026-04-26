import Foundation

enum MuesliCLIContract {
    static let schemaVersion = "1.0"

    static func specData() throws -> Data {
        try encoder.encode(MuesliCLISpec.current)
    }

    static func successData<T: Encodable>(
        command: String,
        result: T,
        warnings: [MuesliCLIWarning] = []
    ) throws -> Data {
        try encoder.encode(MuesliCLISuccessEnvelope(command: command, result: result, warnings: warnings))
    }

    static func errorData(command: String, message: String, fix: String? = nil, code: String = "command_failed") throws -> Data {
        try encoder.encode(MuesliCLIErrorEnvelope(command: command, error: MuesliCLIError(code: code, message: message, fix: fix)))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

struct MuesliCLISpec: Encodable {
    let schemaVersion: String
    let commands: [MuesliCLICommandSpec]

    static let current = MuesliCLISpec(
        schemaVersion: MuesliCLIContract.schemaVersion,
        commands: [
            MuesliCLICommandSpec(
                name: "spec",
                summary: "Print this machine-readable command contract.",
                arguments: []
            ),
            MuesliCLICommandSpec(
                name: "transcribe",
                summary: "Import and transcribe one or more audio files.",
                arguments: [
                    MuesliCLIArgumentSpec(name: "files", required: true, repeatable: true, summary: "Audio files to transcribe."),
                    MuesliCLIArgumentSpec(name: "--profile", required: false, repeatable: false, summary: "Dictionary profile name to use."),
                    MuesliCLIArgumentSpec(name: "--export", required: false, repeatable: false, summary: "Optional export format: txt, md, docx, json, or srt."),
                    MuesliCLIArgumentSpec(name: "--output", required: false, repeatable: false, summary: "Directory for exported transcripts.")
                ]
            ),
            MuesliCLICommandSpec(
                name: "export",
                summary: "Export existing saved transcripts.",
                arguments: [
                    MuesliCLIArgumentSpec(name: "--format", required: true, repeatable: false, summary: "Export format: txt, md, docx, json, or srt."),
                    MuesliCLIArgumentSpec(name: "--output", required: true, repeatable: false, summary: "Directory for exported transcripts."),
                    MuesliCLIArgumentSpec(name: "--query", required: false, repeatable: false, summary: "Filter saved transcripts by text.")
                ]
            )
        ]
    )
}

struct MuesliCLICommandSpec: Encodable {
    let name: String
    let summary: String
    let arguments: [MuesliCLIArgumentSpec]
}

struct MuesliCLIArgumentSpec: Encodable {
    let name: String
    let required: Bool
    let repeatable: Bool
    let summary: String
}

struct MuesliCLIWarning: Encodable, Hashable {
    let code: String
    let message: String
    let fix: String?
}

struct MuesliCLISuccessEnvelope<T: Encodable>: Encodable {
    let ok = true
    let schemaVersion = MuesliCLIContract.schemaVersion
    let command: String
    let result: T
    let warnings: [MuesliCLIWarning]
}

struct MuesliCLIErrorEnvelope: Encodable {
    let ok = false
    let schemaVersion = MuesliCLIContract.schemaVersion
    let command: String
    let error: MuesliCLIError
}

struct MuesliCLIError: Encodable {
    let code: String
    let message: String
    let fix: String?
}
