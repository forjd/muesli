import AVFoundation
import Foundation

struct VoiceActivityChunkRotationTests {
    static func run() throws {
        try rotatesAfterMinimumDurationAndTrailingSilence()
        try waitsForSpeechPauseBeforeMaximumDuration()
        try fallsBackToMaximumDuration()
        try fixedRotationMatchesLegacyDuration()
    }

    private static func rotatesAfterMinimumDurationAndTrailingSilence() throws {
        let rotation = VoiceActivityChunkRotation(
            configuration: VoiceActivityChunkRotation.Configuration(
                minimumDuration: 1.0,
                maximumDuration: 8.0,
                trailingSilenceDuration: 0.4,
                speechPowerThreshold: -45
            ),
            sampleRate: 1_000
        )

        try expect(!rotation.shouldRotate(chunkFrames: 1_300, trailingSilenceFrames: 300), "Expected chunk to wait for the configured silence window")
        try expect(rotation.shouldRotate(chunkFrames: 1_400, trailingSilenceFrames: 400), "Expected chunk to rotate at a speech pause after the minimum duration")
    }

    private static func waitsForSpeechPauseBeforeMaximumDuration() throws {
        let rotation = VoiceActivityChunkRotation(
            configuration: VoiceActivityChunkRotation.Configuration(
                minimumDuration: 1.0,
                maximumDuration: 8.0,
                trailingSilenceDuration: 0.4,
                speechPowerThreshold: -45
            ),
            sampleRate: 1_000
        )

        try expect(rotation.isSpeech(power: -30), "Expected louder buffers to count as speech")
        try expect(!rotation.isSpeech(power: -60), "Expected quiet buffers to count as silence")
        try expect(!rotation.shouldRotate(chunkFrames: 3_000, trailingSilenceFrames: 0), "Expected active speech to continue past the minimum duration")
    }

    private static func fallsBackToMaximumDuration() throws {
        let rotation = VoiceActivityChunkRotation(
            configuration: VoiceActivityChunkRotation.Configuration(
                minimumDuration: 1.0,
                maximumDuration: 8.0,
                trailingSilenceDuration: 0.4,
                speechPowerThreshold: -45
            ),
            sampleRate: 1_000
        )

        try expect(rotation.shouldRotate(chunkFrames: 8_000, trailingSilenceFrames: 0), "Expected maximum duration to prevent unbounded live chunks")
    }

    private static func fixedRotationMatchesLegacyDuration() throws {
        let rotation = VoiceActivityChunkRotation.fixed(duration: 1.0, sampleRate: 1_000)

        try expect(!rotation.shouldRotate(chunkFrames: 999, trailingSilenceFrames: 999), "Expected fixed rotation to wait for its duration")
        try expect(rotation.shouldRotate(chunkFrames: 1_000, trailingSilenceFrames: 0), "Expected fixed rotation to rotate at its duration")
    }
}
