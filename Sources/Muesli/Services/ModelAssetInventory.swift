import FluidAudio
import Foundation

enum ModelAssetKind: String, Hashable, Codable {
    case asr
    case diarization
    case vocabularyBoosting

    var label: String {
        switch self {
        case .asr:
            "ASR"
        case .diarization:
            "Diarization"
        case .vocabularyBoosting:
            "Vocabulary"
        }
    }
}

struct ModelAssetState: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var kind: ModelAssetKind
    var isCached: Bool
    var isSelected: Bool
    var supportsDownload: Bool
    var cacheURL: URL
    var sizeBytes: Int64

    var cacheSizeLabel: String {
        guard sizeBytes > 0 else { return "No local files" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

enum ModelAssetInventory {
    static func states(selectedModel: ParakeetModel) -> [ModelAssetState] {
        let asrStates = ParakeetModel.allCases.map { model in
            let cacheURL = asrCacheURL(for: model)
            return ModelAssetState(
                id: "asr-\(model.rawValue)",
                title: model.label,
                detail: model.detail,
                kind: .asr,
                isCached: asrModelIsCached(model),
                isSelected: model == selectedModel,
                supportsDownload: true,
                cacheURL: cacheURL,
                sizeBytes: directorySize(at: cacheURL)
            )
        }

        let diarizationURL = OfflineDiarizerModels.defaultModelsDirectory()
            .appending(path: Repo.diarizer.folderName, directoryHint: .isDirectory)
        let liveDiarizationURL = OfflineDiarizerModels.defaultModelsDirectory()
            .appending(path: Repo.lseend.folderName, directoryHint: .isDirectory)
        let ctcURL = CtcModels.defaultCacheDirectory()

        return asrStates + [
            ModelAssetState(
                id: "diarization-offline",
                title: "Speaker diarization",
                detail: "Offline meeting speaker labels and speaker-separated exports.",
                kind: .diarization,
                isCached: FluidAudioDiarizer.offlineModelsAreCached(),
                isSelected: false,
                supportsDownload: true,
                cacheURL: diarizationURL,
                sizeBytes: directorySize(at: diarizationURL)
            ),
            ModelAssetState(
                id: "diarization-live",
                title: "Live speaker diarization",
                detail: "Live LS-EEND speaker labels during meeting recording.",
                kind: .diarization,
                isCached: FluidAudioDiarizer.lseendModelsAreCached(),
                isSelected: false,
                supportsDownload: true,
                cacheURL: liveDiarizationURL,
                sizeBytes: directorySize(at: liveDiarizationURL)
            ),
            ModelAssetState(
                id: "vocabulary-ctc",
                title: "Vocabulary boosting",
                detail: "CTC model used for final-pass dictionary rescoring.",
                kind: .vocabularyBoosting,
                isCached: CtcModels.modelsExist(at: ctcURL),
                isSelected: false,
                supportsDownload: false,
                cacheURL: ctcURL,
                sizeBytes: directorySize(at: ctcURL)
            )
        ]
    }

    static func deleteCache(for asset: ModelAssetState) throws {
        guard FileManager.default.fileExists(atPath: asset.cacheURL.path) else { return }
        try FileManager.default.removeItem(at: asset.cacheURL)
    }

    static func baseModelsDirectory() -> URL {
        MLModelConfigurationUtils.defaultModelsDirectory()
    }

    private static func asrModelIsCached(_ model: ParakeetModel) -> Bool {
        let version = asrVersion(for: model)
        let cacheURL = AsrModels.defaultCacheDirectory(for: version)
        return AsrModels.modelsExist(at: cacheURL, version: version)
    }

    private static func asrCacheURL(for model: ParakeetModel) -> URL {
        AsrModels.defaultCacheDirectory(for: asrVersion(for: model))
    }

    private static func asrVersion(for model: ParakeetModel) -> AsrModelVersion {
        switch model {
        case .v2:
            .v2
        case .v3:
            .v3
        }
    }

    private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
