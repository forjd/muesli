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
    var isStableUpdate: Bool
}

enum TranscriptionError: LocalizedError {
    case invalidAudio(URL)
    case audioConversionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidAudio(url):
            "Could not read audio at \(url.path)."
        case let .audioConversionFailed(message):
            "Could not prepare audio for FluidAudio: \(message)"
        }
    }
}

actor ParakeetTranscriber {
    private var fluidAudio = FluidAudioBackend()

    func transcribe(audioURL: URL, model: ParakeetModel) async throws -> TranscriptionResult {
        try await fluidAudio.transcribe(audioURL: audioURL, model: model)
    }

    func preload(model: ParakeetModel) async throws {
        try await fluidAudio.preload(model: model)
    }

    func startStreaming(sessionID: TranscriptSession.ID, model: ParakeetModel) async throws {
        try await fluidAudio.startStreaming(sessionID: sessionID, model: model)
    }

    func streamChunk(sessionID: TranscriptSession.ID, chunkURL: URL, model: ParakeetModel) async throws -> StreamingTranscriptionResult? {
        try await fluidAudio.streamChunk(sessionID: sessionID, chunkURL: chunkURL, model: model)
    }

    func finishStreaming(sessionID: TranscriptSession.ID) async {
        await fluidAudio.finishStreaming(sessionID: sessionID)
    }

    func reset() async {
        await fluidAudio.cleanup()
    }

    func health() async -> TranscriberHealth {
        await fluidAudio.health()
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

    func health() async -> TranscriberHealth {
        TranscriberHealth(
            isRunning: asrManager != nil,
            modelVersion: activeVersion.map { String(describing: $0) }
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
        guard absoluteSampleCount - lastTranscribedSampleCount >= sampleRate / 2 else { return nil }
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
            words: agreement.words,
            isStableUpdate: !agreement.newlyConfirmedText.isEmpty
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

struct TranscriberHealth: Hashable {
    let isRunning: Bool
    let modelVersion: String?
}
