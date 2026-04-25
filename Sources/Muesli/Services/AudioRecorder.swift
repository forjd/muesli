import AVFoundation
import Foundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private let stateLock = NSLock()
    private var outputFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var latestPower: Float = -80

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

    func start() throws -> URL {
        stop()

        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Muesli/Recordings", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = "recording-\(Self.timestamp()).wav"
        let url = directory.appending(path: filename)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.unsupportedFormat
        }

        let outputFile = try AVAudioFile(forWriting: url, settings: outputFormat.settings)
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        stateLock.lock()
        self.outputFile = outputFile
        self.converter = converter
        self.outputFormat = outputFormat
        latestPower = -80
        stateLock.unlock()

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
        return url
    }

    func stop() {
        if engine.inputNode.numberOfInputs > 0 {
            engine.inputNode.removeTap(onBus: 0)
        }

        if engine.isRunning {
            engine.stop()
        }

        stateLock.lock()
        outputFile = nil
        converter = nil
        outputFormat = nil
        latestPower = -80
        stateLock.unlock()
    }

    func currentPower() -> Float {
        stateLock.lock()
        let power = latestPower
        stateLock.unlock()
        return power
    }

    private func handle(buffer: AVAudioPCMBuffer) {
        stateLock.lock()
        guard let outputFile, let converter, let outputFormat else {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 8
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }

        var didProvideInput = false
        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error) { _, status in
            if didProvideInput {
                status.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            status.pointee = .haveData
            return buffer
        }

        guard error == nil, convertedBuffer.frameLength > 0 else {
            return
        }

        do {
            try outputFile.write(from: convertedBuffer)
            updatePower(from: convertedBuffer)
        } catch {
            stateLock.lock()
            latestPower = -80
            stateLock.unlock()
        }
    }

    private func updatePower(from buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.int16ChannelData?[0], buffer.frameLength > 0 else {
            return
        }

        var sum: Double = 0
        for index in 0..<Int(buffer.frameLength) {
            let normalized = Double(samples[index]) / Double(Int16.max)
            sum += normalized * normalized
        }

        let rms = sqrt(sum / Double(buffer.frameLength))
        let db = rms > 0 ? Float(20 * log10(rms)) : -80

        stateLock.lock()
        latestPower = max(-80, min(0, db))
        stateLock.unlock()
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
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
