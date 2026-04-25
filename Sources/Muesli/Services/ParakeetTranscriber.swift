@preconcurrency import AVFoundation
import FluidAudio
import Foundation

struct TranscriptionResult: Decodable {
    var text: String
    var model: String
}

struct StreamingTranscriptionResult: Hashable {
    var text: String
    var newlyConfirmedText: String
    var words: [TimedWord]
}

enum TranscriptionError: LocalizedError {
    case missingScript
    case missingPython([String])
    case failed(status: Int32, output: String)
    case invalidOutput(String)
    case workerUnavailable(String)
    case invalidAudio(URL)
    case audioConversionFailed(String)

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
        case let .invalidAudio(url):
            "Could not read audio at \(url.path)."
        case let .audioConversionFailed(message):
            "Could not prepare audio for FluidAudio: \(message)"
        }
    }
}

actor ParakeetTranscriber {
    private var worker: WorkerProcess?
    private var fluidAudio = FluidAudioBackend()

    deinit {
        worker?.stop()
    }

    func transcribe(audioURL: URL, model: ParakeetModel, backend: ParakeetBackend) async throws -> TranscriptionResult {
        switch backend {
        case .fluidAudio:
            return try await fluidAudio.transcribe(audioURL: audioURL, model: model)
        case .python:
            return try transcribeWithPython(audioURL: audioURL, model: model)
        }
    }

    func preload(model: ParakeetModel, backend: ParakeetBackend) async throws {
        switch backend {
        case .fluidAudio:
            try await fluidAudio.preload(model: model)
        case .python:
            try preloadPython(model: model)
        }
    }

    func startStreaming(sessionID: TranscriptSession.ID, model: ParakeetModel, backend: ParakeetBackend) async throws {
        guard backend == .fluidAudio else { return }
        try await fluidAudio.startStreaming(sessionID: sessionID, model: model)
    }

    func streamChunk(sessionID: TranscriptSession.ID, chunkURL: URL, model: ParakeetModel, backend: ParakeetBackend) async throws -> StreamingTranscriptionResult? {
        guard backend == .fluidAudio else { return nil }
        return try await fluidAudio.streamChunk(sessionID: sessionID, chunkURL: chunkURL, model: model)
    }

    func finishStreaming(sessionID: TranscriptSession.ID, backend: ParakeetBackend) async {
        guard backend == .fluidAudio else { return }
        await fluidAudio.finishStreaming(sessionID: sessionID)
    }

    func stopWorker() async {
        worker?.stop()
        worker = nil
        await fluidAudio.cleanup()
    }

    func health(backend: ParakeetBackend) async throws -> WorkerHealth {
        switch backend {
        case .fluidAudio:
            return await fluidAudio.health()
        case .python:
            if let worker {
                return WorkerHealth(
                    backend: backend,
                    isRunning: worker.isRunning,
                    processID: worker.process.processIdentifier,
                    logURL: worker.errorLogURL
                )
            }

            let pythonURL = try resolvePythonExecutable()
            return WorkerHealth(
                backend: backend,
                isRunning: false,
                processID: nil,
                logURL: workerLogURL(pythonURL: pythonURL)
            )
        }
    }

    private func transcribeWithPython(audioURL: URL, model: ParakeetModel) throws -> TranscriptionResult {
        let worker = try ensureWorker()
        let request = WorkerRequest(id: UUID().uuidString, type: "transcribe", model: model.rawValue, audio: audioURL.path)
        let response = try worker.send(request)

        guard response.ok else {
            throw TranscriptionError.workerUnavailable(response.error ?? "Unknown worker error")
        }

        return TranscriptionResult(text: response.text ?? "", model: response.model ?? model.rawValue)
    }

    private func preloadPython(model: ParakeetModel) throws {
        let worker = try ensureWorker()
        let request = WorkerRequest(id: UUID().uuidString, type: "preload", model: model.rawValue, audio: nil)
        let response = try worker.send(request)

        guard response.ok else {
            throw TranscriptionError.workerUnavailable(response.error ?? "Unknown worker error")
        }
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

private actor FluidAudioBackend {
    private var asrManager: AsrManager?
    private var cachedModels: AsrModels?
    private var activeVersion: AsrModelVersion?
    private var streamingSessions: [TranscriptSession.ID: FluidAudioStreamingSession] = [:]

    func transcribe(audioURL: URL, model: ParakeetModel) async throws -> TranscriptionResult {
        let manager = try await ensureManager(for: model)
        let samples = try Self.readMono16kSamples(from: audioURL)

        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return TranscriptionResult(text: result.text, model: model.rawValue)
    }

    func preload(model: ParakeetModel) async throws {
        _ = try await ensureManager(for: model)
    }

    func startStreaming(sessionID: TranscriptSession.ID, model: ParakeetModel) async throws {
        _ = try await ensureManager(for: model)
        streamingSessions[sessionID] = FluidAudioStreamingSession(model: model)
    }

    func streamChunk(sessionID: TranscriptSession.ID, chunkURL: URL, model: ParakeetModel) async throws -> StreamingTranscriptionResult? {
        let manager = try await ensureManager(for: model)
        let samples = try Self.readMono16kSamples(from: chunkURL)

        let session: FluidAudioStreamingSession
        if let existing = streamingSessions[sessionID] {
            session = existing
        } else {
            session = FluidAudioStreamingSession(model: model)
            streamingSessions[sessionID] = session
        }

        return try await session.append(samples: samples, manager: manager)
    }

    func finishStreaming(sessionID: TranscriptSession.ID) {
        streamingSessions[sessionID] = nil
    }

    func cleanup() async {
        await asrManager?.cleanup()
        asrManager = nil
        activeVersion = nil
        streamingSessions.removeAll()
    }

    func health() async -> WorkerHealth {
        WorkerHealth(
            backend: .fluidAudio,
            isRunning: asrManager != nil,
            processID: nil,
            logURL: nil
        )
    }

    private func ensureManager(for model: ParakeetModel) async throws -> AsrManager {
        let version = model.asrVersion
        if let asrManager, activeVersion == version {
            return asrManager
        }

        await asrManager?.cleanup()
        asrManager = nil
        activeVersion = nil

        let models: AsrModels
        if let cachedModels, cachedModels.version == version {
            models = cachedModels
        } else {
            models = try await AsrModels.downloadAndLoad(version: version)
            cachedModels = models
        }

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        asrManager = manager
        activeVersion = version
        return manager
    }

    private static func readMono16kSamples(from url: URL) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw TranscriptionError.invalidAudio(url)
        }

        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw TranscriptionError.invalidAudio(url)
        }

        do {
            try file.read(into: inputBuffer)
        } catch {
            throw TranscriptionError.invalidAudio(url)
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw TranscriptionError.audioConversionFailed("Could not create 16 kHz mono format.")
        }

        guard let converter = AVAudioConverter(from: file.processingFormat, to: outputFormat) else {
            throw TranscriptionError.audioConversionFailed("No converter from \(file.processingFormat) to \(outputFormat).")
        }

        let ratio = outputFormat.sampleRate / file.processingFormat.sampleRate
        let outputCapacity = AVAudioFrameCount((Double(inputBuffer.frameLength) * ratio).rounded(.up)) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            throw TranscriptionError.audioConversionFailed("Could not allocate converted audio buffer.")
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if didProvideInput {
                inputStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }

        if let conversionError {
            throw TranscriptionError.audioConversionFailed(conversionError.localizedDescription)
        }

        guard status != .error, let channelData = outputBuffer.floatChannelData?[0] else {
            throw TranscriptionError.audioConversionFailed("Converter returned \(status).")
        }

        let frameCount = Int(outputBuffer.frameLength)
        guard frameCount > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: channelData, count: frameCount))
    }
}

private final class FluidAudioStreamingSession {
    private let sampleRate = 16_000
    private let agreementEngine = WordAgreementEngine()
    private var audioBuffer: [Float] = []
    private var trimmedSampleCount = 0
    private var lastTranscribedSampleCount = 0
    private var decoderLayerCount: Int?
    private let model: ParakeetModel

    init(model: ParakeetModel) {
        self.model = model
    }

    func append(samples: [Float], manager: AsrManager) async throws -> StreamingTranscriptionResult? {
        audioBuffer.append(contentsOf: samples)

        let absoluteSampleCount = trimmedSampleCount + audioBuffer.count
        guard absoluteSampleCount - lastTranscribedSampleCount >= sampleRate else { return nil }
        guard absoluteSampleCount >= sampleRate else { return nil }

        let seekTime = agreementEngine.hypothesisStartTime > 0
            ? agreementEngine.hypothesisStartTime
            : agreementEngine.confirmedEndTime
        let seekSample = max(0, Int(seekTime * Double(sampleRate)))
        let relativeSeek = max(0, seekSample - trimmedSampleCount)
        guard relativeSeek < audioBuffer.count else { return nil }

        var slice = Array(audioBuffer[relativeSeek..<audioBuffer.count])
        guard slice.count >= sampleRate else { return nil }

        if slice.count + sampleRate <= 240_000 {
            slice += [Float](repeating: 0, count: sampleRate)
        }

        if decoderLayerCount == nil {
            decoderLayerCount = await manager.decoderLayerCount
        }

        let layerCount: Int
        if let decoderLayerCount {
            layerCount = decoderLayerCount
        } else {
            layerCount = await manager.decoderLayerCount
            self.decoderLayerCount = layerCount
        }

        var decoderState = TdtDecoderState.make(decoderLayers: layerCount)
        let result = try await manager.transcribe(slice, decoderState: &decoderState)
        lastTranscribedSampleCount = absoluteSampleCount

        let timeOffset = Double(seekSample) / Double(sampleRate)
        let words = WordAgreementEngine.mergeTokensToWords(result.tokenTimings ?? [], timeOffset: timeOffset)

        let agreement: AgreementResult
        if words.isEmpty {
            let fallbackWords = result.text
                .split(separator: " ")
                .enumerated()
                .map { offset, word in
                    TimedWord(
                        text: String(word),
                        startTime: timeOffset + Double(offset) * 0.35,
                        endTime: timeOffset + Double(offset + 1) * 0.35,
                        confidence: result.confidence
                    )
                }
            agreement = agreementEngine.process(words: fallbackWords, confidence: result.confidence)
        } else {
            agreement = agreementEngine.process(words: words, confidence: result.confidence)
        }

        trimConfirmedAudio()

        return StreamingTranscriptionResult(
            text: TextNormalizer.shared.normalizeSentence(agreement.fullText),
            newlyConfirmedText: TextNormalizer.shared.normalizeSentence(agreement.newlyConfirmedText),
            words: agreement.words
        )
    }

    private func trimConfirmedAudio() {
        let trimTime = agreementEngine.hypothesisStartTime > 0
            ? agreementEngine.hypothesisStartTime
            : agreementEngine.confirmedEndTime
        let trimSample = max(0, Int(trimTime * Double(sampleRate)))
        let samplesToTrim = trimSample - trimmedSampleCount
        guard samplesToTrim > sampleRate, !audioBuffer.isEmpty else { return }

        let trimCount = min(samplesToTrim, audioBuffer.count)
        audioBuffer.removeFirst(trimCount)
        trimmedSampleCount += trimCount
    }
}

private extension ParakeetModel {
    var asrVersion: AsrModelVersion {
        switch self {
        case .v2:
            .v2
        case .v3:
            .v3
        }
    }
}

struct WorkerHealth: Hashable {
    let backend: ParakeetBackend
    let isRunning: Bool
    let processID: Int32?
    let logURL: URL?
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
    let errorLogURL: URL

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
