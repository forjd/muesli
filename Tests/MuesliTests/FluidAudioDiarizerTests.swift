import FluidAudio
import Foundation

struct FluidAudioDiarizerTests {
    static func run() throws {
        try testOfflineModelCacheDetectionRequiresAllFiles()
        try testOfflineModelCacheDetectionAcceptsCompleteCache()
        try testMissingOfflineModelsThrowDownloadRequired()
        try testSpeakerTurnsUseFirstSeenSpeakerLabels()
    }

    private static func testOfflineModelCacheDetectionRequiresAllFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try createOfflineModelCache(in: directory, missing: [ModelNames.OfflineDiarizer.embeddingPath])

        try expect(!FluidAudioDiarizer.offlineModelsAreCached(in: directory), "Expected partial diarizer cache to be rejected")
    }

    private static func testOfflineModelCacheDetectionAcceptsCompleteCache() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try createOfflineModelCache(in: directory)

        try expect(FluidAudioDiarizer.offlineModelsAreCached(in: directory), "Expected complete diarizer cache to be accepted")
    }

    private static func testMissingOfflineModelsThrowDownloadRequired() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            try FluidAudioDiarizer.requireCachedOfflineModels(in: directory)
            throw TestFailure("Expected missing diarizer models to throw")
        } catch DiarizationError.diarizationModelDownloadRequired {
        }
    }

    private static func testSpeakerTurnsUseFirstSeenSpeakerLabels() throws {
        let segments = [
            TimedSpeakerSegment(speakerId: "z", embedding: [], startTimeSeconds: 5, endTimeSeconds: 6, qualityScore: 0.8),
            TimedSpeakerSegment(speakerId: "a", embedding: [], startTimeSeconds: 1, endTimeSeconds: 2, qualityScore: 0.8),
            TimedSpeakerSegment(speakerId: "z", embedding: [], startTimeSeconds: 3, endTimeSeconds: 4, qualityScore: 0.8)
        ]

        let turns = FluidAudioDiarizer.speakerTurns(from: segments)

        try expectEqual(turns.map(\.speakerID), ["a", "z", "z"])
        try expectEqual(turns.map(\.speakerLabel), ["Speaker 1", "Speaker 2", "Speaker 2"])
    }

    private static func createOfflineModelCache(in directory: URL, missing: Set<String> = []) throws {
        let repoDirectory = directory.appending(path: Repo.diarizer.folderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repoDirectory, withIntermediateDirectories: true)
        for modelName in ModelNames.OfflineDiarizer.requiredModels where !missing.contains(modelName) {
            let url = repoDirectory.appending(path: modelName)
            if modelName.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try Data("{}".utf8).write(to: url)
            }
        }
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MuesliDiarizerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
