@preconcurrency import CoreML
import FluidAudio
import Foundation

struct SpeakerTurn: Hashable {
    var speakerID: String
    var speakerLabel: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var qualityScore: Float
}

enum DiarizationError: LocalizedError {
    case diarizationModelDownloadRequired
    case missingPLDAParameters(URL)
    case invalidPLDAParameters(URL)

    var errorDescription: String? {
        switch self {
        case .diarizationModelDownloadRequired:
            "FluidAudio speaker diarization models are not cached."
        case let .missingPLDAParameters(url):
            "FluidAudio diarization PLDA parameters are missing at \(url.path)."
        case let .invalidPLDAParameters(url):
            "FluidAudio diarization PLDA parameters could not be decoded at \(url.path)."
        }
    }
}

actor FluidAudioDiarizer {
    private var manager = OfflineDiarizerManager()
    private var liveDiarizer: LSEENDDiarizer?

    func prepare(allowsModelDownload: Bool) async throws {
        if allowsModelDownload {
            try await manager.prepareModels()
        } else {
            try Self.requireCachedOfflineModels()
            let models = try await Self.loadCachedOfflineModels(from: OfflineDiarizerModels.defaultModelsDirectory())
            manager.initialize(models: models)
        }
    }

    func startLive(allowsModelDownload: Bool) async throws {
        if !allowsModelDownload {
            try Self.requireCachedLSEENDModels()
        }
        let diarizer = LSEENDDiarizer()
        let descriptor = try await LSEENDModelDescriptor.loadFromHuggingFace(variant: .dihard3)
        try diarizer.initialize(descriptor: descriptor)
        liveDiarizer = diarizer
    }

    func diarizeLiveChunk(chunkURL: URL) async throws -> [SpeakerTurn] {
        guard let liveDiarizer else { return [] }
        let samples = try AudioConverter().resampleAudioFile(chunkURL)
        _ = try liveDiarizer.process(samples: samples, sourceSampleRate: 16_000)
        return Self.speakerTurns(fromDiarizerSegments: liveDiarizer.timeline.speakers.values.flatMap(\.finalizedSegments))
    }

    @discardableResult
    func finishLive() -> [SpeakerTurn] {
        let speakerTurns: [SpeakerTurn]
        if let liveDiarizer {
            liveDiarizer.timeline.finalize()
            speakerTurns = Self.speakerTurns(fromDiarizerSegments: liveDiarizer.timeline.speakers.values.flatMap(\.finalizedSegments))
            liveDiarizer.reset()
        } else {
            speakerTurns = []
        }
        liveDiarizer = nil
        return speakerTurns
    }

    func diarize(
        audioURL: URL,
        allowsModelDownload: Bool,
        modelsDirectory: URL = OfflineDiarizerModels.defaultModelsDirectory()
    ) async throws -> [SpeakerTurn] {
        if allowsModelDownload {
            try await manager.prepareModels(directory: modelsDirectory)
        } else {
            try Self.requireCachedOfflineModels(in: modelsDirectory)
            let models = try await Self.loadCachedOfflineModels(from: modelsDirectory)
            manager.initialize(models: models)
        }

        let result = try await manager.process(audioURL)
        return Self.speakerTurns(from: result.segments)
    }

    static func offlineModelsAreCached(in modelsDirectory: URL = OfflineDiarizerModels.defaultModelsDirectory()) -> Bool {
        (try? requireCachedOfflineModels(in: modelsDirectory)) != nil
    }

    static func lseendModelsAreCached(in modelsDirectory: URL = OfflineDiarizerModels.defaultModelsDirectory()) -> Bool {
        (try? requireCachedLSEENDModels(in: modelsDirectory)) != nil
    }

    static func requireCachedOfflineModels(in modelsDirectory: URL = OfflineDiarizerModels.defaultModelsDirectory()) throws {
        let repoDirectory = modelsDirectory.appending(path: Repo.diarizer.folderName, directoryHint: .isDirectory)
        let fileManager = FileManager.default
        let hasRequiredModels = ModelNames.OfflineDiarizer.requiredModels.allSatisfy { modelName in
            fileManager.fileExists(atPath: repoDirectory.appending(path: modelName).path)
        }
        guard hasRequiredModels else {
            throw DiarizationError.diarizationModelDownloadRequired
        }
    }

    static func speakerTurns(from segments: [TimedSpeakerSegment]) -> [SpeakerTurn] {
        var speakerLabels: [String: String] = [:]

        return segments
            .sorted { lhs, rhs in
                if lhs.startTimeSeconds == rhs.startTimeSeconds {
                    return lhs.speakerId < rhs.speakerId
                }
                return lhs.startTimeSeconds < rhs.startTimeSeconds
            }
            .map { segment in
                let label = speakerLabels[segment.speakerId] ?? {
                    let label = "Speaker \(speakerLabels.count + 1)"
                    speakerLabels[segment.speakerId] = label
                    return label
                }()

                return SpeakerTurn(
                    speakerID: segment.speakerId,
                    speakerLabel: label,
                    startTime: TimeInterval(segment.startTimeSeconds),
                    endTime: TimeInterval(segment.endTimeSeconds),
                    qualityScore: segment.qualityScore
                )
            }
    }

    static func speakerTurns(fromDiarizerSegments segments: [DiarizerSegment]) -> [SpeakerTurn] {
        var speakerLabels: [String: String] = [:]

        return segments
            .sorted { lhs, rhs in
                if lhs.startTime == rhs.startTime {
                    return lhs.speakerIndex < rhs.speakerIndex
                }
                return lhs.startTime < rhs.startTime
            }
            .map { segment in
                let speakerID = String(segment.speakerIndex)
                let label = speakerLabels[speakerID] ?? {
                    let label = "Speaker \(speakerLabels.count + 1)"
                    speakerLabels[speakerID] = label
                    return label
                }()
                return SpeakerTurn(
                    speakerID: speakerID,
                    speakerLabel: label,
                    startTime: TimeInterval(segment.startTime),
                    endTime: TimeInterval(segment.endTime),
                    qualityScore: segment.activity
                )
            }
    }

    private static func requireCachedLSEENDModels(in modelsDirectory: URL = OfflineDiarizerModels.defaultModelsDirectory()) throws {
        let repoDirectory = modelsDirectory.appending(path: Repo.lseend.folderName, directoryHint: .isDirectory)
        let fileManager = FileManager.default
        let hasRequiredModels = LSEENDVariant.dihard3.fileNames.allSatisfy { fileName in
            fileManager.fileExists(atPath: repoDirectory.appending(path: fileName).path)
        }
        guard hasRequiredModels else {
            throw DiarizationError.diarizationModelDownloadRequired
        }
    }

    private static func loadCachedOfflineModels(from modelsDirectory: URL) async throws -> OfflineDiarizerModels {
        let repoDirectory = modelsDirectory.appending(path: Repo.diarizer.folderName, directoryHint: .isDirectory)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        configuration.allowLowPrecisionAccumulationOnGPU = true

        let segmentation = try MLModel(
            contentsOf: repoDirectory.appending(path: ModelNames.OfflineDiarizer.segmentationPath),
            configuration: configuration
        )
        let fbankConfiguration = MLModelConfiguration()
        fbankConfiguration.computeUnits = .cpuOnly
        fbankConfiguration.allowLowPrecisionAccumulationOnGPU = true
        let fbank = try MLModel(
            contentsOf: repoDirectory.appending(path: ModelNames.OfflineDiarizer.fbankPath),
            configuration: fbankConfiguration
        )
        let embedding = try MLModel(
            contentsOf: repoDirectory.appending(path: ModelNames.OfflineDiarizer.embeddingPath),
            configuration: configuration
        )
        let pldaRho = try MLModel(
            contentsOf: repoDirectory.appending(path: ModelNames.OfflineDiarizer.pldaRhoPath),
            configuration: configuration
        )
        let pldaPsi = try loadPLDAPsi(from: repoDirectory)

        return OfflineDiarizerModels(
            segmentationModel: segmentation,
            fbankModel: fbank,
            embeddingModel: embedding,
            pldaRhoModel: pldaRho,
            pldaPsi: pldaPsi,
            compilationDuration: 0
        )
    }

    private static func loadPLDAPsi(from repoDirectory: URL) throws -> [Double] {
        let parametersURL = repoDirectory.appending(path: ModelNames.OfflineDiarizer.pldaParameters)
        guard FileManager.default.fileExists(atPath: parametersURL.path) else {
            throw DiarizationError.missingPLDAParameters(parametersURL)
        }

        let data = try Data(contentsOf: parametersURL)
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard
            let root = jsonObject as? [String: Any],
            let tensors = root["tensors"] as? [String: Any],
            let psiInfo = tensors["psi"] as? [String: Any],
            let base64 = psiInfo["data_base64"] as? String,
            let decoded = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters])
        else {
            throw DiarizationError.invalidPLDAParameters(parametersURL)
        }

        let floatCount = decoded.count / MemoryLayout<Float>.size
        guard floatCount > 0 else {
            throw DiarizationError.invalidPLDAParameters(parametersURL)
        }

        var floats = [Float](repeating: 0, count: floatCount)
        _ = floats.withUnsafeMutableBytes { destination in
            decoded.copyBytes(to: destination)
        }
        return floats.map { Double($0) }
    }
}
