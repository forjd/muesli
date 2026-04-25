import Foundation

struct TranscriptionResult: Decodable {
    var text: String
    var model: String
}

enum TranscriptionError: LocalizedError {
    case missingScript
    case missingPython([String])
    case failed(status: Int32, output: String)
    case invalidOutput(String)
    case workerUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingScript:
            "The bundled Parakeet sidecar script could not be found."
        case let .missingPython(candidates):
            "No Python environment found for Parakeet. Run ./script/setup_python.sh or set MUESLI_PYTHON. Checked: \(candidates.joined(separator: ", "))"
        case let .failed(status, output):
            "Parakeet sidecar exited with status \(status): \(output)"
        case let .invalidOutput(output):
            "The sidecar returned invalid JSON: \(output)"
        case let .workerUnavailable(message):
            "Parakeet worker is unavailable: \(message)"
        }
    }
}

actor ParakeetTranscriber {
    private var worker: WorkerProcess?

    deinit {
        worker?.stop()
    }

    func transcribe(audioURL: URL, model: ParakeetModel) async throws -> TranscriptionResult {
        let worker = try ensureWorker()
        let request = WorkerRequest(id: UUID().uuidString, type: "transcribe", model: model.rawValue, audio: audioURL.path)
        let response = try worker.send(request)

        guard response.ok else {
            throw TranscriptionError.workerUnavailable(response.error ?? "Unknown worker error")
        }

        return TranscriptionResult(text: response.text ?? "", model: response.model ?? model.rawValue)
    }

    func preload(model: ParakeetModel) async throws {
        let worker = try ensureWorker()
        let request = WorkerRequest(id: UUID().uuidString, type: "preload", model: model.rawValue, audio: nil)
        let response = try worker.send(request)

        guard response.ok else {
            throw TranscriptionError.workerUnavailable(response.error ?? "Unknown worker error")
        }
    }

    func stopWorker() {
        worker?.stop()
        worker = nil
    }

    private func ensureWorker() throws -> WorkerProcess {
        if let worker, worker.isRunning {
            return worker
        }

        let pythonURL = try resolvePythonExecutable()
        let environment = sidecarEnvironment(pythonURL: pythonURL)

        guard let scriptURL = Bundle.module.url(forResource: "parakeet_transcribe", withExtension: "py") else {
            throw TranscriptionError.missingScript
        }

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [scriptURL.path, "--worker"]
        process.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorLogURL = workerLogURL(pythonURL: pythonURL)
        try FileManager.default.createDirectory(
            at: errorLogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: errorLogURL.path, contents: nil)
        let errorLog = try FileHandle(forWritingTo: errorLogURL)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorLog

        try process.run()

        let worker = WorkerProcess(
            process: process,
            input: inputPipe.fileHandleForWriting,
            output: outputPipe.fileHandleForReading,
            errorLog: errorLog,
            errorLogURL: errorLogURL
        )
        self.worker = worker
        return worker
    }

    private func resolvePythonExecutable() throws -> URL {
        let fileManager = FileManager.default
        let candidates = pythonCandidates()

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        throw TranscriptionError.missingPython(candidates.map(\.path))
    }

    private func pythonCandidates() -> [URL] {
        var candidates: [URL] = []

        if let override = ProcessInfo.processInfo.environment["MUESLI_PYTHON"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(currentDirectory.appending(path: ".venv/bin/python"))

        let bundleURL = Bundle.main.bundleURL
        let projectRootFromDist = bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        candidates.append(projectRootFromDist.appending(path: ".venv/bin/python"))

        if let resourceURL = Bundle.module.resourceURL {
            let packageRootFromBuild = resourceURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            candidates.append(packageRootFromBuild.appending(path: ".venv/bin/python"))
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            seen.insert(candidate.path).inserted
        }
    }

    private func sidecarEnvironment(pythonURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["TOKENIZERS_PARALLELISM"] = "false"

        let venvDirectory = pythonURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectRoot = venvDirectory.deletingLastPathComponent()
        environment["HF_HOME"] = projectRoot.appending(path: ".cache/huggingface").path
        environment["NEMO_HOME"] = projectRoot.appending(path: ".cache/nemo").path
        return environment
    }

    private func workerLogURL(pythonURL: URL) -> URL {
        let venvDirectory = pythonURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectRoot = venvDirectory.deletingLastPathComponent()
        return projectRoot.appending(path: ".cache/muesli-worker.log")
    }
}

private struct WorkerRequest: Encodable {
    let id: String
    let type: String
    let model: String
    let audio: String?
}

private struct WorkerResponse: Decodable {
    let id: String
    let ok: Bool
    let text: String?
    let model: String?
    let error: String?
}

private final class WorkerProcess {
    let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let errorLog: FileHandle
    private let errorLogURL: URL

    init(process: Process, input: FileHandle, output: FileHandle, errorLog: FileHandle, errorLogURL: URL) {
        self.process = process
        self.input = input
        self.output = output
        self.errorLog = errorLog
        self.errorLogURL = errorLogURL
    }

    var isRunning: Bool {
        process.isRunning
    }

    func send(_ request: WorkerRequest) throws -> WorkerResponse {
        guard process.isRunning else {
            throw TranscriptionError.workerUnavailable(readErrorOutput())
        }

        let data = try JSONEncoder().encode(request)
        input.write(data)
        input.write(Data([0x0A]))

        while process.isRunning {
            guard let line = output.readLine() else {
                throw TranscriptionError.workerUnavailable(readErrorOutput())
            }

            guard let lineData = line.data(using: .utf8) else {
                continue
            }

            do {
                let response = try JSONDecoder().decode(WorkerResponse.self, from: lineData)
                if response.id == request.id {
                    return response
                }
            } catch {
                continue
            }
        }

        throw TranscriptionError.workerUnavailable(readErrorOutput())
    }

    func stop() {
        guard process.isRunning else { return }

        let shutdown = #"{"type":"shutdown"}"# + "\n"
        if let data = shutdown.data(using: .utf8) {
            try? input.write(contentsOf: data)
        }

        process.terminate()
        try? errorLog.close()
    }

    private func readErrorOutput() -> String {
        guard let data = try? Data(contentsOf: errorLogURL), !data.isEmpty else {
            return "worker exited without output"
        }
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            return "worker exited without output"
        }
        return String(output.suffix(4_000))
    }
}

private extension FileHandle {
    func readLine() -> String? {
        var data = Data()

        while true {
            let chunk = readData(ofLength: 1)
            if chunk.isEmpty {
                return data.isEmpty ? nil : String(data: data, encoding: .utf8)
            }

            if chunk[0] == 0x0A {
                return String(data: data, encoding: .utf8)
            }

            data.append(chunk)
        }
    }
}
