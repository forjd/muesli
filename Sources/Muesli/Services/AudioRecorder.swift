import AVFoundation
import Foundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private let stateLock = NSLock()
    private let processingQueue = DispatchQueue(label: "muesli.audio-recorder.processing")
    private var outputFile: AVAudioFile?
    private var chunkFile: AVAudioFile?
    private var chunkDirectory: URL?
    private var chunkIndex = 0
    private var chunkFrameCount: AVAudioFramePosition = 0
    private var chunkSilenceFrameCount: AVAudioFramePosition = 0
    private var totalChunkFrames: AVAudioFramePosition = 0
    private var chunkPeakPower: Float = -80
    private var chunkRotation: VoiceActivityChunkRotation?
    private var onChunk: ((RecordingChunk) -> Void)?
    private var recordingFormat: AVAudioFormat?
    private var latestPower: Float = -80
    private var hasInstalledTap = false
    private var isStopping = false
    private let speechPowerThreshold: Float = -45

    var isRecording: Bool {
        engine.isRunning
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start(
        chunkDuration: TimeInterval? = nil,
        vadConfiguration: VoiceActivityChunkRotation.Configuration? = nil,
        onChunk: ((RecordingChunk) -> Void)? = nil
    ) throws -> URL {
        stop()

        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Muesli/Recordings", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = "recording-\(Self.timestamp()).wav"
        let url = directory.appending(path: filename)
        let chunkDirectory = directory
            .appending(path: "Chunks", directoryHint: .isDirectory)
            .appending(path: url.deletingPathExtension().lastPathComponent, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: chunkDirectory, withIntermediateDirectories: true)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let outputFile = try AVAudioFile(forWriting: url, settings: inputFormat.settings)

        stateLock.lock()
        isStopping = false
        self.outputFile = outputFile
        self.recordingFormat = inputFormat
        self.chunkDirectory = chunkDirectory
        self.chunkFile = nil
        self.chunkIndex = 0
        self.chunkFrameCount = 0
        self.chunkSilenceFrameCount = 0
        self.totalChunkFrames = 0
        self.chunkPeakPower = -80
        if let vadConfiguration {
            self.chunkRotation = VoiceActivityChunkRotation(configuration: vadConfiguration, sampleRate: inputFormat.sampleRate)
        } else if let chunkDuration {
            self.chunkRotation = VoiceActivityChunkRotation.fixed(duration: chunkDuration, sampleRate: inputFormat.sampleRate)
        } else {
            self.chunkRotation = nil
        }
        self.onChunk = onChunk
        latestPower = -80
        stateLock.unlock()

        if hasInstalledTap {
            inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let copiedBuffer = Self.copyBuffer(buffer) else { return }
            self.processingQueue.async { [weak self] in
                self?.handle(buffer: copiedBuffer)
            }
        }
        hasInstalledTap = true

        engine.prepare()
        try engine.start()
        return url
    }

    func stop() {
        stateLock.lock()
        isStopping = true
        stateLock.unlock()

        if hasInstalledTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        if engine.isRunning {
            engine.stop()
        }

        flushOpenChunk()

        processingQueue.sync {
            stateLock.lock()
            outputFile = nil
            chunkFile = nil
            chunkDirectory = nil
            chunkIndex = 0
            chunkFrameCount = 0
            chunkSilenceFrameCount = 0
            totalChunkFrames = 0
            chunkPeakPower = -80
            chunkRotation = nil
            onChunk = nil
            recordingFormat = nil
            latestPower = -80
            isStopping = false
            stateLock.unlock()
        }
    }

    func currentPower() -> Float {
        stateLock.lock()
        let power = latestPower
        stateLock.unlock()
        return power
    }

    private func handle(buffer: AVAudioPCMBuffer) {
        stateLock.lock()
        guard !isStopping, let outputFile, let recordingFormat else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        do {
            try outputFile.write(from: buffer)
            let power = calculatePower(from: buffer)
            updatePower(power)
            try writeChunk(from: buffer, format: recordingFormat, power: power)
        } catch {
            stateLock.lock()
            latestPower = -80
            stateLock.unlock()
        }
    }

    private func writeChunk(from buffer: AVAudioPCMBuffer, format: AVAudioFormat, power: Float) throws {
        stateLock.lock()
        guard let rotation = chunkRotation, let chunkDirectory else {
            stateLock.unlock()
            return
        }

        if chunkFile == nil {
            chunkIndex += 1
            chunkFrameCount = 0
            chunkSilenceFrameCount = 0
            chunkPeakPower = -80
            let url = chunkDirectory.appending(path: String(format: "chunk-%04d.wav", chunkIndex))
            do {
                chunkFile = try AVAudioFile(forWriting: url, settings: format.settings)
            } catch {
                stateLock.unlock()
                throw error
            }
        }

        guard let chunkFile else {
            stateLock.unlock()
            return
        }

        let chunkURL = chunkFile.url
        do {
            try chunkFile.write(from: buffer)
        } catch {
            stateLock.unlock()
            throw error
        }
        chunkFrameCount += AVAudioFramePosition(buffer.frameLength)
        if rotation.isSpeech(power: power) {
            chunkSilenceFrameCount = 0
        } else {
            chunkSilenceFrameCount += AVAudioFramePosition(buffer.frameLength)
        }
        chunkPeakPower = max(chunkPeakPower, power)

        guard rotation.shouldRotate(chunkFrames: chunkFrameCount, trailingSilenceFrames: chunkSilenceFrameCount) else {
            stateLock.unlock()
            return
        }

        let finishedChunk = finishCurrentChunkLocked(url: chunkURL, format: format)
        let callback = onChunk
        stateLock.unlock()

        publish(finishedChunk, callback: callback)
    }

    private func flushOpenChunk() {
        processingQueue.sync {
            stateLock.lock()
            guard let chunkFile, let recordingFormat else {
                stateLock.unlock()
                return
            }

            let finishedChunk = finishCurrentChunkLocked(url: chunkFile.url, format: recordingFormat)
            let callback = onChunk
            stateLock.unlock()

            publish(finishedChunk, callback: callback)
        }
    }

    private func finishCurrentChunkLocked(url: URL, format: AVAudioFormat) -> RecordingChunk {
        let finishedIndex = chunkIndex
        let finishedDuration = Double(chunkFrameCount) / format.sampleRate
        let finishedStartTime = Double(totalChunkFrames) / format.sampleRate
        let finishedEndTime = finishedStartTime + finishedDuration
        let finishedPeakPower = chunkPeakPower

        chunkFile = nil
        totalChunkFrames += chunkFrameCount
        chunkFrameCount = 0
        chunkSilenceFrameCount = 0
        chunkPeakPower = -80

        return RecordingChunk(
            url: url,
            index: finishedIndex,
            duration: finishedDuration,
            startTime: finishedStartTime,
            endTime: finishedEndTime,
            peakPower: finishedPeakPower
        )
    }

    private func publish(_ chunk: RecordingChunk, callback: ((RecordingChunk) -> Void)?) {
        guard chunk.peakPower >= speechPowerThreshold else {
            return
        }

        callback?(chunk)
    }

    private func calculatePower(from buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return -80 }

        var sum: Double = 0

        if let samples = buffer.floatChannelData?[0] {
            for index in 0..<frameLength {
                let sample = Double(samples[index])
                sum += sample * sample
            }
        } else if let samples = buffer.int16ChannelData?[0] {
            for index in 0..<frameLength {
                let normalized = Double(samples[index]) / Double(Int16.max)
                sum += normalized * normalized
            }
        } else {
            return -80
        }

        let rms = sqrt(sum / Double(frameLength))
        let db = rms > 0 ? Float(20 * log10(rms)) : -80
        return max(-80, min(0, db))
    }

    private func updatePower(_ db: Float) {
        stateLock.lock()
        latestPower = db
        stateLock.unlock()
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }

        copy.frameLength = buffer.frameLength

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)

        if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            let byteCount = frameCount * MemoryLayout<Float>.size
            for channel in 0..<channelCount {
                memcpy(destination[channel], source[channel], byteCount)
            }
            return copy
        }

        if let source = buffer.int16ChannelData, let destination = copy.int16ChannelData {
            let byteCount = frameCount * MemoryLayout<Int16>.size
            for channel in 0..<channelCount {
                memcpy(destination[channel], source[channel], byteCount)
            }
            return copy
        }

        return nil
    }
}

struct RecordingChunk: Sendable {
    let url: URL
    let index: Int
    let duration: TimeInterval
    let startTime: TimeInterval
    let endTime: TimeInterval
    let peakPower: Float
}

enum AudioRecorderError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "Could not create a 16 kHz mono recording format."
        }
    }
}
