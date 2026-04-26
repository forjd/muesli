import AVFoundation
import Foundation

enum MuesliCLI {
    static let commandNames: Set<String> = ["spec", "transcribe", "export"]

    static func run(arguments: [String]) -> Int32 {
        guard let command = arguments.first else {
            writeError(command: "unknown", message: "Missing command.", fix: "Run `Muesli spec` to inspect supported commands.")
            return 64
        }

        do {
            switch command {
            case "spec":
                write(try MuesliCLIContract.specData())
                return 0
            case "export":
                try export(arguments: Array(arguments.dropFirst()))
                return 0
            case "transcribe":
                return runAsync {
                    try await transcribe(arguments: Array(arguments.dropFirst()))
                }
            default:
                writeError(command: command, message: "Unknown command.", fix: "Run `Muesli spec` to inspect supported commands.")
                return 64
            }
        } catch let error as CLIUsageError {
            writeError(command: command, message: error.message, fix: error.fix, code: "usage_error")
            return 64
        } catch {
            writeError(command: command, message: error.localizedDescription)
            return 1
        }
    }

    private static func export(arguments: [String]) throws {
        let options = try ParsedOptions(arguments: arguments, valueOptions: ["--format", "--output", "--query"])
        guard let formatValue = options.value(for: "--format"), let format = TranscriptExportFormat(cliValue: formatValue) else {
            throw CLIUsageError(message: "Missing or unsupported export format.", fix: "Pass `--format txt`, `md`, `docx`, `json`, or `srt`.")
        }
        guard let outputValue = options.value(for: "--output") else {
            throw CLIUsageError(message: "Missing output directory.", fix: "Pass `--output /path/to/folder`.")
        }

        let outputDirectory = URL(filePath: outputValue)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let query = options.value(for: "--query") ?? ""
        let sessions = TranscriptSessionFilter(searchText: query)
            .apply(to: try loadPlaintextSessionsForCLI())
            .filter { !$0.displayTranscript.isEmpty }
        let urls = BatchExportPlanner.destinationURLs(for: sessions, format: format, outputDirectory: outputDirectory)
        var exported: [CLIExportedFile] = []
        var warnings: [MuesliCLIWarning] = []

        for session in sessions {
            guard let url = urls[session.id] else { continue }
            do {
                try TranscriptExporter.data(for: session, format: format).write(to: url, options: [.atomic])
                exported.append(CLIExportedFile(sessionID: session.id, path: url.path))
            } catch {
                warnings.append(MuesliCLIWarning(code: "export_failed", message: "\(url.lastPathComponent): \(error.localizedDescription)", fix: "Check output folder permissions."))
            }
        }

        let result = CLIExportResult(count: exported.count, files: exported)
        write(try MuesliCLIContract.successData(command: "export", result: result, warnings: warnings))
    }

    private static func transcribe(arguments: [String]) async throws {
        let options = try ParsedOptions(arguments: arguments, valueOptions: ["--profile", "--export", "--output"])
        guard !options.positionals.isEmpty else {
            throw CLIUsageError(message: "Missing audio file.", fix: "Pass one or more WAV, M4A, MP3, AIFF, or CAF files.")
        }

        let model = selectedModel()
        let transcriber = ParakeetTranscriber()
        if UserDefaults.standard.bool(forKey: "offlineMode"), await transcriber.isModelCached(model) == false {
            throw CLIUsageError(message: "Offline mode is on and \(model.label) is not cached.", fix: "Turn off offline mode once in Muesli to download the selected model.")
        }

        let profile = dictionaryProfile(named: options.value(for: "--profile"))
        let exportFormat = options.value(for: "--export").flatMap(TranscriptExportFormat.init(cliValue:))
        let outputDirectory = options.value(for: "--output").map { URL(filePath: $0) }
        if exportFormat != nil, outputDirectory == nil {
            throw CLIUsageError(message: "Missing output directory for export.", fix: "Pass `--output /path/to/folder`.")
        }
        if let outputDirectory {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }

        var processed: [CLITranscribedFile] = []
        var warnings: [MuesliCLIWarning] = []

        for path in options.positionals {
            let sourceURL = URL(filePath: path)
            guard AudioImportFormat.isSupported(sourceURL) else {
                warnings.append(MuesliCLIWarning(code: "unsupported_format", message: "\(sourceURL.lastPathComponent) was skipped.", fix: "Use WAV, M4A, MP3, AIFF, or CAF."))
                continue
            }

            do {
                let result = try await transcriber.transcribe(audioURL: sourceURL, model: model)
                let corrected = CustomDictionaryEngine(terms: profile?.terms ?? []).apply(to: result.text.trimmingCharacters(in: .whitespacesAndNewlines))
                var session = TranscriptSession(
                    audioURL: sourceURL,
                    model: model,
                    status: .complete,
                    transcript: corrected,
                    finalTranscript: corrected,
                    duration: audioDuration(at: sourceURL),
                    fileSize: fileSize(at: sourceURL)
                )
                session.status = .complete

                var exportPath: String?
                if let exportFormat, let outputDirectory {
                    let url = BatchExportPlanner.destinationURLs(for: [session], format: exportFormat, outputDirectory: outputDirectory)[session.id]!
                    try TranscriptExporter.data(for: session, format: exportFormat).write(to: url, options: [.atomic])
                    exportPath = url.path
                }
                processed.append(CLITranscribedFile(sessionID: session.id, sourcePath: sourceURL.path, transcriptLength: corrected.count, exportPath: exportPath))
            } catch {
                warnings.append(MuesliCLIWarning(code: "transcription_failed", message: "\(sourceURL.lastPathComponent): \(error.localizedDescription)", fix: "Check the file path and that the selected model is available."))
            }
        }

        let result = CLITranscribeResult(count: processed.count, files: processed)
        write(try MuesliCLIContract.successData(command: "transcribe", result: result, warnings: warnings))
    }

    private static func loadPlaintextSessionsForCLI() throws -> [TranscriptSession] {
        let persistence = SessionPersistence()
        guard let data = try? Data(contentsOf: persistence.sessionsURL) else {
            return []
        }
        guard SecureStorage().isEncrypted(data) == false else {
            throw CLIUsageError(
                message: "Saved transcript history is encrypted and cannot be unlocked from this CLI context.",
                fix: "Use in-app export for saved history, or run `Muesli transcribe ... --export ...` for file-based CLI exports."
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TranscriptSession].self, from: data)
    }

    private static func selectedModel() -> ParakeetModel {
        guard let rawValue = UserDefaults.standard.string(forKey: "selectedModel"),
              let model = ParakeetModel(rawValue: rawValue) else {
            return .v3
        }
        return model
    }

    private static func dictionaryProfile(named name: String?) -> CustomDictionaryProfile? {
        let profiles: [CustomDictionaryProfile]
        if let data = UserDefaults.standard.data(forKey: "customDictionaryProfiles"),
           let decoded = try? JSONDecoder().decode([CustomDictionaryProfile].self, from: data) {
            profiles = decoded
        } else {
            profiles = CustomDictionaryProfile.defaultProfiles
        }

        guard let name, !name.isEmpty else {
            return profiles.first { $0.id == CustomDictionaryProfile.generalID } ?? profiles.first
        }
        return profiles.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private static func audioDuration(at url: URL) -> TimeInterval? {
        guard let audioFile = try? AVAudioFile(forReading: url),
              audioFile.processingFormat.sampleRate > 0 else {
            return nil
        }
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber else {
            return nil
        }
        return size.int64Value
    }

    private static func runAsync(_ operation: @escaping () async throws -> Void) -> Int32 {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box {
            var result: Result<Void, Error>?
        }
        let box = Box()

        Task {
            do {
                try await operation()
                box.result = .success(())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        switch box.result {
        case .success:
            return 0
        case let .failure(error as CLIUsageError):
            writeError(command: "transcribe", message: error.message, fix: error.fix, code: "usage_error")
            return 64
        case let .failure(error):
            writeError(command: "transcribe", message: error.localizedDescription)
            return 1
        case .none:
            writeError(command: "transcribe", message: "Command did not complete.")
            return 1
        }
    }

    private static func write(_ data: Data) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeError(command: String, message: String, fix: String? = nil, code: String = "command_failed") {
        let data = (try? MuesliCLIContract.errorData(command: command, message: message, fix: fix, code: code)) ?? Data()
        FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data("\n".utf8))
    }
}

private struct ParsedOptions {
    var values: [String: String] = [:]
    var positionals: [String] = []

    init(arguments: [String], valueOptions: Set<String>) throws {
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            if valueOptions.contains(argument) {
                let valueIndex = arguments.index(after: index)
                guard valueIndex < arguments.endIndex else {
                    throw CLIUsageError(message: "Missing value for \(argument).", fix: "Run `Muesli spec` to inspect command arguments.")
                }
                values[argument] = arguments[valueIndex]
                index = arguments.index(after: valueIndex)
            } else if argument.hasPrefix("--") {
                throw CLIUsageError(message: "Unsupported option \(argument).", fix: "Run `Muesli spec` to inspect command arguments.")
            } else {
                positionals.append(argument)
                index = arguments.index(after: index)
            }
        }
    }

    func value(for name: String) -> String? {
        values[name]
    }
}

private struct CLIUsageError: Error {
    let message: String
    let fix: String?
}

private struct CLIExportResult: Encodable {
    let count: Int
    let files: [CLIExportedFile]
}

private struct CLIExportedFile: Encodable {
    let sessionID: UUID
    let path: String
}

private struct CLITranscribeResult: Encodable {
    let count: Int
    let files: [CLITranscribedFile]
}

private struct CLITranscribedFile: Encodable {
    let sessionID: UUID
    let sourcePath: String
    let transcriptLength: Int
    let exportPath: String?
}

private extension TranscriptExportFormat {
    init?(cliValue: String) {
        switch cliValue.lowercased() {
        case "txt", "text":
            self = .text
        case "md", "markdown":
            self = .markdown
        case "docx":
            self = .docx
        case "json":
            self = .json
        case "srt":
            self = .srt
        default:
            return nil
        }
    }
}
