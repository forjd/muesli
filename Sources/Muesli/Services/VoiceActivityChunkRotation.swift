import AVFoundation
import Foundation

struct VoiceActivityChunkRotation: Sendable {
    struct Configuration: Equatable, Sendable {
        var minimumDuration: TimeInterval = 1.0
        var maximumDuration: TimeInterval = 8.0
        var trailingSilenceDuration: TimeInterval = 0.45
        var speechPowerThreshold: Float = -45

        init(
            minimumDuration: TimeInterval = 1.0,
            maximumDuration: TimeInterval = 8.0,
            trailingSilenceDuration: TimeInterval = 0.45,
            speechPowerThreshold: Float = -45
        ) {
            self.minimumDuration = minimumDuration
            self.maximumDuration = max(maximumDuration, minimumDuration)
            self.trailingSilenceDuration = trailingSilenceDuration
            self.speechPowerThreshold = speechPowerThreshold
        }
    }

    private let minimumFrames: AVAudioFramePosition
    private let maximumFrames: AVAudioFramePosition
    private let trailingSilenceFrames: AVAudioFramePosition
    private let speechPowerThreshold: Float

    init(configuration: Configuration, sampleRate: Double) {
        minimumFrames = AVAudioFramePosition(configuration.minimumDuration * sampleRate)
        maximumFrames = AVAudioFramePosition(configuration.maximumDuration * sampleRate)
        trailingSilenceFrames = AVAudioFramePosition(configuration.trailingSilenceDuration * sampleRate)
        speechPowerThreshold = configuration.speechPowerThreshold
    }

    static func fixed(duration: TimeInterval, sampleRate: Double) -> VoiceActivityChunkRotation {
        VoiceActivityChunkRotation(
            configuration: Configuration(
                minimumDuration: duration,
                maximumDuration: duration,
                trailingSilenceDuration: duration,
                speechPowerThreshold: .greatestFiniteMagnitude
            ),
            sampleRate: sampleRate
        )
    }

    func isSpeech(power: Float) -> Bool {
        power >= speechPowerThreshold
    }

    func shouldRotate(chunkFrames: AVAudioFramePosition, trailingSilenceFrames: AVAudioFramePosition) -> Bool {
        if chunkFrames >= maximumFrames {
            return true
        }

        return chunkFrames >= minimumFrames && trailingSilenceFrames >= self.trailingSilenceFrames
    }
}
