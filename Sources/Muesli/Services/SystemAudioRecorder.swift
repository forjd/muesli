import AVFoundation
import Foundation
import ScreenCaptureKit

@MainActor
final class SystemAudioRecorder: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var hasStartedWriting = false

    var isRecording: Bool {
        stream != nil
    }

    func start(recordingsDirectory: URL) async throws -> URL {
        stop()
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        let url = recordingsDirectory.appending(path: "meeting-system-\(Self.timestamp()).m4a")
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw SystemAudioRecorderError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = false
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let assetWriter = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ]
        )
        audioInput.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(audioInput) else {
            throw SystemAudioRecorderError.cannotCreateWriter
        }
        assetWriter.add(audioInput)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "muesli.system-audio"))

        self.stream = stream
        self.assetWriter = assetWriter
        self.audioInput = audioInput
        self.outputURL = url
        self.hasStartedWriting = false

        try await stream.startCapture()
        return url
    }

    func stop() {
        let stream = stream
        let assetWriter = assetWriter
        let audioInput = audioInput

        self.stream = nil
        self.assetWriter = nil
        self.audioInput = nil
        self.outputURL = nil
        self.hasStartedWriting = false

        if let stream {
            Task {
                try? await stream.stopCapture()
            }
        }

        audioInput?.markAsFinished()
        if let assetWriter, assetWriter.status == .writing {
            assetWriter.finishWriting {}
        } else if let assetWriter, assetWriter.status == .unknown {
            assetWriter.cancelWriting()
        }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        Task { @MainActor in
            appendAudioSampleBuffer(sampleBuffer)
        }
    }

    private func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let assetWriter,
              let audioInput else {
            return
        }

        if !hasStartedWriting {
            guard assetWriter.startWriting() else { return }
            assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            hasStartedWriting = true
        }

        guard assetWriter.status == .writing,
              audioInput.isReadyForMoreMediaData else {
            return
        }

        audioInput.append(sampleBuffer)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

enum SystemAudioRecorderError: LocalizedError {
    case noDisplay
    case cannotCreateWriter

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            "No display is available for system audio capture."
        case .cannotCreateWriter:
            "Could not create a system audio recording file."
        }
    }
}
