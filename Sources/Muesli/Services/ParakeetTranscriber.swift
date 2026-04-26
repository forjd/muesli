@preconcurrency import AVFoundation
import FluidAudio
import Foundation

struct TranscriptionResult: Decodable {
    var text: String
    var model: String
    var vocabularyBoosting: VocabularyBoostingResult?
}

struct VocabularyBoostingRequest: Hashable {
    var terms: [String]
    var allowsModelDownload: Bool
}

struct VocabularyBoostingResult: Hashable, Codable {
    enum Status: String, Hashable, Codable {
        case skipped
        case applied
        case unavailable
        case failed
    }

    var status: Status
    var detectedTerms: [String]
    var appliedTerms: [String]
    var message: String
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
    case ctcModelDownloadRequired

    var errorDescription: String? {
        switch self {
        case let .invalidAudio(url):
            "Could not read audio at \(url.path)."
        case let .audioConversionFailed(message):
            "Could not prepare audio for FluidAudio: \(message)"
        case .ctcModelDownloadRequired:
            "FluidAudio CTC vocabulary boosting models are not cached."
        }
    }
}

actor ParakeetTranscriber {
    private var fluidAudio = FluidAudioBackend()

    func transcribe(
        audioURL: URL,
        model: ParakeetModel,
        vocabularyBoosting: VocabularyBoostingRequest? = nil
    ) async throws -> TranscriptionResult {
        try await fluidAudio.transcribe(audioURL: audioURL, model: model, vocabularyBoosting: vocabularyBoosting)
    }

    func preload(model: ParakeetModel) async throws {
        try await fluidAudio.preload(model: model)
    }

    func isModelCached(_ model: ParakeetModel) async -> Bool {
        await fluidAudio.isModelCached(model)
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
    private var ctcModels: CtcModels?
    private var activeVersion: AsrModelVersion?
    private var streamingSessions: [TranscriptSession.ID: FluidAudioStreamingSession] = [:]

    func transcribe(
        audioURL: URL,
        model: ParakeetModel,
        vocabularyBoosting: VocabularyBoostingRequest?
    ) async throws -> TranscriptionResult {
        let manager = try await ensureManager(for: model)
        let samples = try Self.readMono16kSamples(from: audioURL)

        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        let boosted = await applyVocabularyBoostingIfNeeded(
            request: vocabularyBoosting,
            samples: samples,
            result: result
        )
        return TranscriptionResult(text: boosted.text, model: model.rawValue, vocabularyBoosting: boosted.metadata)
    }

    func preload(model: ParakeetModel) async throws {
        _ = try await ensureManager(for: model)
    }

    func isModelCached(_ model: ParakeetModel) -> Bool {
        let version = model.asrVersion
        let cacheDirectory = AsrModels.defaultCacheDirectory(for: version)
        return AsrModels.modelsExist(at: cacheDirectory, version: version)
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
        ctcModels = nil
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
            let cacheDirectory = AsrModels.defaultCacheDirectory(for: version)
            if AsrModels.modelsExist(at: cacheDirectory, version: version) {
                models = try await AsrModels.loadFromCache(version: version)
            } else {
                models = try await AsrModels.downloadAndLoad(version: version)
            }
            cachedModels = models
        }

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        asrManager = manager
        activeVersion = version
        return manager
    }

    private func ensureCtcModels(allowsDownload: Bool) async throws -> CtcModels {
        if let ctcModels {
            return ctcModels
        }

        let cacheDirectory = CtcModels.defaultCacheDirectory()
        let models: CtcModels
        if CtcModels.modelsExist(at: cacheDirectory) {
            models = try await CtcModels.load(from: cacheDirectory)
        } else {
            guard allowsDownload else {
                throw TranscriptionError.ctcModelDownloadRequired
            }
            models = try await CtcModels.downloadAndLoad()
        }
        ctcModels = models
        return models
    }

    private func applyVocabularyBoostingIfNeeded(
        request: VocabularyBoostingRequest?,
        samples: [Float],
        result: ASRResult
    ) async -> (text: String, metadata: VocabularyBoostingResult?) {
        guard let request else {
            return (result.text, nil)
        }

        let terms = Self.normalizedVocabularyTerms(request.terms)
        guard !terms.isEmpty else {
            return (
                result.text,
                VocabularyBoostingResult(
                    status: .skipped,
                    detectedTerms: [],
                    appliedTerms: [],
                    message: "Vocabulary boosting skipped because the selected dictionary profile has no enabled terms."
                )
            )
        }

        guard let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty else {
            return (
                result.text,
                VocabularyBoostingResult(
                    status: .unavailable,
                    detectedTerms: [],
                    appliedTerms: [],
                    message: "Vocabulary boosting unavailable because FluidAudio did not return token timings."
                )
            )
        }

        do {
            let ctcModels = try await ensureCtcModels(allowsDownload: request.allowsModelDownload)
            let tokenizer = try await CtcTokenizer.load(from: CtcModels.defaultCacheDirectory(for: ctcModels.variant))
            let vocabularyTerms = terms.compactMap { term -> CustomVocabularyTerm? in
                let tokenIDs = tokenizer.encode(term)
                guard !tokenIDs.isEmpty else { return nil }
                return CustomVocabularyTerm(text: term, ctcTokenIds: tokenIDs)
            }

            guard !vocabularyTerms.isEmpty else {
                return (
                    result.text,
                    VocabularyBoostingResult(
                        status: .unavailable,
                        detectedTerms: [],
                        appliedTerms: [],
                        message: "Vocabulary boosting unavailable because no dictionary terms could be tokenized."
                    )
                )
            }

            let vocabulary = CustomVocabularyContext(terms: vocabularyTerms)
            let spotter = CtcKeywordSpotter(models: ctcModels, blankId: ctcModels.vocabulary.count)
            let spotResult = try await spotter.spotKeywordsWithLogProbs(
                audioSamples: samples,
                customVocabulary: vocabulary
            )
            let rescorer = try await VocabularyRescorer.create(
                spotter: spotter,
                vocabulary: vocabulary,
                ctcModelDirectory: CtcModels.defaultCacheDirectory(for: ctcModels.variant)
            )
            let rescoreOutput = rescorer.ctcTokenRescore(
                transcript: result.text,
                tokenTimings: tokenTimings,
                logProbs: spotResult.logProbs,
                frameDuration: spotResult.frameDuration
            )
            let detectedTerms = spotResult.detections.map(\.term.text)
            let appliedTerms = rescoreOutput.replacements
                .filter(\.shouldReplace)
                .compactMap(\.replacementWord)

            return (
                rescoreOutput.text,
                VocabularyBoostingResult(
                    status: rescoreOutput.wasModified ? .applied : .skipped,
                    detectedTerms: Array(Set(detectedTerms)).sorted(),
                    appliedTerms: Array(Set(appliedTerms)).sorted(),
                    message: rescoreOutput.wasModified
                        ? "Vocabulary boosting applied \(appliedTerms.count) replacement(s)."
                        : "Vocabulary boosting ran; no higher-confidence replacements were applied."
                )
            )
        } catch TranscriptionError.ctcModelDownloadRequired {
            return (
                result.text,
                VocabularyBoostingResult(
                    status: .unavailable,
                    detectedTerms: [],
                    appliedTerms: [],
                    message: "Vocabulary boosting needs the FluidAudio CTC model download. Turn off offline mode and transcribe again to cache it."
                )
            )
        } catch {
            return (
                result.text,
                VocabularyBoostingResult(
                    status: .failed,
                    detectedTerms: [],
                    appliedTerms: [],
                    message: "Vocabulary boosting failed; using the regular transcript. \(error.localizedDescription)"
                )
            )
        }
    }

    private static func normalizedVocabularyTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms.compactMap { term in
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
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
