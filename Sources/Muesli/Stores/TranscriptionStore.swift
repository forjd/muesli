import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

@MainActor
final class TranscriptionStore: ObservableObject {
    @Published var sessions: [TranscriptSession] = []
    @Published var selectedSessionID: TranscriptSession.ID?
    @Published var isRecording = false
    @Published var isBusy = false
    @Published var currentAudioLevel: Float = -80
    @Published var selectedModel: ParakeetModel = .v3
    @Published var statusMessage = "Ready"
    @Published var isWarmingModel = false
    @Published var modelLoadState: ModelLoadState = .idle
    @Published var recordingElapsed: TimeInterval = 0
    @Published var liveChunkStats: [TranscriptSession.ID: LiveChunkStats] = [:]
    @Published var transcriberHealth: TranscriberHealth?

    private let recorder = AudioRecorder()
    private let transcriber = ParakeetTranscriber()
    private let persistence = SessionPersistence()
    private var activeRecordingURL: URL?
    private var activeSessionID: TranscriptSession.ID?
    private var meterTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var failedLiveChunks: [TranscriptSession.ID: [RecordingChunk]] = [:]
    private var liveChunkQueue: Task<Void, Never>?
    private let longRecordingFinalPassLimit: TimeInterval = 30 * 60

    init() {
        sessions = persistence.load()
        hydrateRecordingMetadata()
        normalizeInterruptedSessions()
        selectedSessionID = sessions.first?.id
    }

    var latestRecordingURL: URL? {
        activeRecordingURL ?? sessions.first?.audioURL
    }

    var selectedSession: TranscriptSession? {
        guard let selectedSessionID else { return sessions.first }
        return sessions.first { $0.id == selectedSessionID }
    }

    func toggleRecording() async {
        if isRecording {
            if let sessionID = stopRecording() {
                await transcribe(sessionID: sessionID)
            }
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        guard !isBusy else { return }

        let granted = await recorder.requestPermission()
        guard granted else {
            statusMessage = "Microphone permission was denied."
            return
        }

        do {
            let url = try recorder.start(chunkDuration: 1) { [weak self] chunk in
                Task { @MainActor [weak self] in
                    self?.handleLiveChunk(chunk)
                }
            }
            let session = TranscriptSession(audioURL: url, model: selectedModel, status: .recording)
            sessions.insert(session, at: 0)
            selectedSessionID = session.id
            activeSessionID = session.id
            liveChunkStats[session.id] = LiveChunkStats()
            activeRecordingURL = url
            isRecording = true
            statusMessage = "Recording..."
            try await transcriber.startStreaming(sessionID: session.id, model: selectedModel)
            scheduleSave()
            startMetering()
            startElapsedTimer()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func stopRecording() -> TranscriptSession.ID? {
        guard isRecording else { return nil }
        recorder.stop()
        liveChunkQueue?.cancel()
        liveChunkQueue = nil
        meterTask?.cancel()
        elapsedTask?.cancel()
        currentAudioLevel = -80
        isRecording = false

        if let activeSessionID, sessions.contains(where: { $0.id == activeSessionID }) {
            statusMessage = "Finalizing recording..."
            self.activeRecordingURL = nil
            self.activeSessionID = nil
            if let index = sessions.firstIndex(where: { $0.id == activeSessionID }),
               sessions[index].status == .recording {
                sessions[index].status = .finalizing
                updateRecordingMetadata(at: index)
            }
            Task {
                await transcriber.finishStreaming(sessionID: activeSessionID)
            }
            scheduleSave()
            return activeSessionID
        }

        activeRecordingURL = nil
        activeSessionID = nil
        return nil
    }

    func transcribeLatestRecording() async {
        var stoppedSessionID: TranscriptSession.ID?
        if isRecording {
            stoppedSessionID = stopRecording()
        }

        if let stoppedSessionID {
            await transcribe(sessionID: stoppedSessionID)
            return
        }

        guard let session = selectedSession ?? sessions.first else {
            statusMessage = "Record audio before transcribing."
            return
        }

        await transcribe(sessionID: session.id)
    }

    func transcribe(sessionID: TranscriptSession.ID) async {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        isBusy = true
        selectedSessionID = sessionID
        sessions[index].status = .transcribing
        sessions[index].errorMessage = nil
        sessions[index].model = selectedModel
        updateRecordingMetadata(at: index)
        statusMessage = "Transcribing with \(selectedModel.label)..."
        scheduleSave()

        let audioURL = sessions[index].audioURL
        let model = selectedModel

        if let duration = sessions[index].duration,
           duration > longRecordingFinalPassLimit,
           !sessions[index].liveTranscript.isEmpty {
            sessions[index].status = .complete
            sessions[index].transcript = sessions[index].liveTranscript
            sessions[index].finalTranscript = ""
            statusMessage = "Skipped final pass for long recording; using live transcript."
            isBusy = false
            scheduleSave()
            return
        }

        do {
            let result = try await transcriber.transcribe(audioURL: audioURL, model: model)
            if let updatedIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
                sessions[updatedIndex].status = .complete
                let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                sessions[updatedIndex].finalTranscript = trimmed
                if !trimmed.isEmpty {
                    sessions[updatedIndex].transcript = trimmed
                } else if !sessions[updatedIndex].liveTranscript.isEmpty {
                    sessions[updatedIndex].transcript = sessions[updatedIndex].liveTranscript
                }
            }
            statusMessage = "Transcription complete."
        } catch {
            if let updatedIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
                sessions[updatedIndex].status = .failed
                sessions[updatedIndex].errorMessage = error.localizedDescription
            }
            statusMessage = error.localizedDescription
        }

        isBusy = false
        scheduleSave()
    }

    private func normalizeInterruptedSessions() {
        var changed = false
        for index in sessions.indices where sessions[index].status == .recording || sessions[index].status == .finalizing || sessions[index].status == .transcribing {
            sessions[index].status = .recorded
            sessions[index].errorMessage = nil
            changed = true
        }

        if changed {
            scheduleSave()
        }
    }

    private func hydrateRecordingMetadata() {
        var changed = false
        for index in sessions.indices where sessions[index].duration == nil || sessions[index].fileSize == nil {
            updateRecordingMetadata(at: index)
            changed = true
        }

        if changed {
            scheduleSave()
        }
    }

    private func updateRecordingMetadata(at index: Int) {
        let url = sessions[index].audioURL
        if let audioFile = try? AVAudioFile(forReading: url), audioFile.processingFormat.sampleRate > 0 {
            sessions[index].duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber {
            sessions[index].fileSize = size.int64Value
        }
    }

    private func handleLiveChunk(_ chunk: RecordingChunk) {
        guard isRecording, let activeSessionID else { return }

        let model = selectedModel
        liveChunkStats[activeSessionID, default: LiveChunkStats()].submitted += 1
        statusMessage = "Transcribing chunk \(chunk.index)..."
        let previousTask = liveChunkQueue
        liveChunkQueue = Task { [weak self] in
            await previousTask?.value
            guard let self else { return }

            do {
                if let result = try await self.transcriber.streamChunk(sessionID: activeSessionID, chunkURL: chunk.url, model: model) {
                    await MainActor.run {
                        self.replaceLiveTranscript(
                            result,
                            sessionID: activeSessionID,
                            chunkIndex: chunk.index
                        )
                    }
                } else {
                    await MainActor.run {
                        self.liveChunkStats[activeSessionID, default: LiveChunkStats()].completed += 1
                    }
                }
            } catch {
                await MainActor.run {
                    self.failedLiveChunks[activeSessionID, default: []].append(chunk)
                    self.liveChunkStats[activeSessionID, default: LiveChunkStats()].failed += 1
                    self.statusMessage = "Chunk \(chunk.index) failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func replaceLiveTranscript(
        _ result: StreamingTranscriptionResult,
        sessionID: TranscriptSession.ID,
        chunkIndex: Int
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        liveChunkStats[sessionID, default: LiveChunkStats()].completed += 1
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            scheduleSave()
            return
        }

        sessions[index].liveTranscript = trimmed
        sessions[index].segments.removeAll { $0.source == .live }
        sessions[index].segments.append(contentsOf: liveSegments(from: result.words, fallbackChunkIndex: chunkIndex))

        if sessions[index].finalTranscript.isEmpty {
            sessions[index].transcript = trimmed
        }

        if isRecording, sessionID == activeSessionID {
            if result.isStableUpdate {
                statusMessage = "Confirmed: \(result.newlyConfirmedText)"
            } else {
                statusMessage = "Listening..."
            }
        }

        scheduleSave()
    }

    private func liveSegments(from words: [TimedWord], fallbackChunkIndex: Int) -> [TranscriptSegment] {
        guard !words.isEmpty else { return [] }

        var segments: [TranscriptSegment] = []
        var currentWords: [TimedWord] = []
        var segmentIndex = fallbackChunkIndex * 1_000

        for word in words {
            currentWords.append(word)
            let shouldFlush = currentWords.count >= 12 || word.text.last.map { [".", "!", "?"].contains($0) } == true
            if shouldFlush {
                segments.append(makeSegment(from: currentWords, chunkIndex: segmentIndex))
                segmentIndex += 1
                currentWords = []
            }
        }

        if !currentWords.isEmpty {
            segments.append(makeSegment(from: currentWords, chunkIndex: segmentIndex))
        }

        return segments
    }

    private func makeSegment(from words: [TimedWord], chunkIndex: Int) -> TranscriptSegment {
        TranscriptSegment(
            chunkIndex: chunkIndex,
            startTime: words.first?.startTime ?? 0,
            endTime: max(words.last?.endTime ?? 0, (words.first?.startTime ?? 0) + 1),
            text: words.map(\.text).joined(separator: " "),
            source: .live
        )
    }

    func retryFailedChunks(sessionID: TranscriptSession.ID) {
        guard let chunks = failedLiveChunks[sessionID], !chunks.isEmpty else {
            statusMessage = "No failed chunks to retry."
            return
        }

        failedLiveChunks[sessionID] = []
        liveChunkStats[sessionID, default: LiveChunkStats()].failed = 0
        statusMessage = "Retrying \(chunks.count) failed chunk\(chunks.count == 1 ? "" : "s")..."

        for chunk in chunks {
            Task { [weak self] in
                guard let self else { return }

                do {
                    if let result = try await self.transcriber.streamChunk(sessionID: sessionID, chunkURL: chunk.url, model: self.selectedModel) {
                        await MainActor.run {
                            self.replaceLiveTranscript(result, sessionID: sessionID, chunkIndex: chunk.index)
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.failedLiveChunks[sessionID, default: []].append(chunk)
                        self.liveChunkStats[sessionID, default: LiveChunkStats()].failed += 1
                        self.statusMessage = "Retry failed for chunk \(chunk.index): \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func prepareTranscriber() async {
        guard !isWarmingModel else { return }

        isWarmingModel = true
        let model = selectedModel
        modelLoadState = .loading(model.label)
        statusMessage = "Preparing \(model.label)..."

        do {
            try await transcriber.preload(model: model)
            if selectedModel == model {
                modelLoadState = .ready(model.label)
                statusMessage = "\(model.label) is ready."
            }
        } catch {
            modelLoadState = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
        }

        isWarmingModel = false
        refreshTranscriberHealth()
    }

    func resetTranscriber() async {
        await transcriber.reset()
        transcriberHealth = nil
        statusMessage = "Resetting transcriber..."
        await prepareTranscriber()
    }

    func refreshTranscriberHealth() {
        Task { [weak self] in
            guard let self else { return }
            let health = await self.transcriber.health()
            await MainActor.run {
                self.transcriberHealth = health
            }
        }
    }

    func copyTranscript(sessionID: TranscriptSession.ID) {
        guard let session = sessions.first(where: { $0.id == sessionID }), !session.transcript.isEmpty else {
            statusMessage = "No transcript to copy."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.displayTranscript, forType: .string)
        statusMessage = "Transcript copied."
    }

    func exportTranscript(sessionID: TranscriptSession.ID, format: TranscriptExportFormat) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        guard !session.displayTranscript.isEmpty else {
            statusMessage = "No transcript to export."
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = exportFilename(for: session, format: format)
        panel.allowedContentTypes = [format.contentType]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try exportData(for: session, format: format)
            try data.write(to: url, options: [.atomic])
            statusMessage = "Exported \(url.lastPathComponent)."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteSession(sessionID: TranscriptSession.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let session = sessions.remove(at: index)
        deleteFiles(for: session)
        liveChunkStats[sessionID] = nil
        failedLiveChunks[sessionID] = nil

        if selectedSessionID == sessionID {
            selectedSessionID = sessions.first?.id
        }

        statusMessage = "Deleted recording."
        scheduleSave()
    }

    func benchmark(sessionID: TranscriptSession.ID) async {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        isBusy = true
        selectedSessionID = sessionID
        statusMessage = "Benchmarking models..."
        sessions[index].benchmarks = []
        scheduleSave()

        let audioURL = sessions[index].audioURL

        for model in ParakeetModel.allCases {
            let started = Date()
            do {
                let result = try await transcriber.transcribe(audioURL: audioURL, model: model)
                let duration = Date().timeIntervalSince(started)
                if let updatedIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
                    sessions[updatedIndex].benchmarks.append(
                        TranscriptionBenchmark(
                            model: model,
                            duration: duration,
                            transcriptLength: result.text.count
                        )
                    )
                }
                statusMessage = "\(model.label): \(duration.formatted(.number.precision(.fractionLength(2))))s"
            } catch {
                statusMessage = "\(model.label) benchmark failed: \(error.localizedDescription)"
            }
            scheduleSave()
        }

        isBusy = false
        statusMessage = "Benchmark complete."
        scheduleSave()
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.currentAudioLevel = self.recorder.currentPower()
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func startElapsedTimer() {
        elapsedTask?.cancel()
        recordingElapsed = 0
        let startedAt = Date()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.recordingElapsed = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func scheduleSave() {
        let sessions = sessions
        let persistence = persistence
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            try? persistence.save(sessions)
        }
    }

    private func deleteFiles(for session: TranscriptSession) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: session.audioURL)

        let chunkDirectory = session.audioURL
            .deletingLastPathComponent()
            .appending(path: "Chunks", directoryHint: .isDirectory)
            .appending(path: session.audioURL.deletingPathExtension().lastPathComponent, directoryHint: .isDirectory)
        try? fileManager.removeItem(at: chunkDirectory)
    }

    private func exportFilename(for session: TranscriptSession, format: TranscriptExportFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "muesli-\(formatter.string(from: session.createdAt)).\(format.fileExtension)"
    }

    private func exportData(for session: TranscriptSession, format: TranscriptExportFormat) throws -> Data {
        switch format {
        case .text:
            return Data(session.displayTranscript.utf8)
        case .json:
            let payload = TranscriptExportPayload(
                id: session.id,
                createdAt: session.createdAt,
                audioPath: session.audioURL.path,
                model: session.model.rawValue,
                transcript: session.displayTranscript,
                liveTranscript: session.liveTranscript,
                finalTranscript: session.finalTranscript,
                segments: session.segments,
                benchmarks: session.benchmarks,
                duration: session.duration,
                fileSize: session.fileSize
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(payload)
        case .srt:
            return Data(srtText(for: session).utf8)
        }
    }

    private func srtText(for session: TranscriptSession) -> String {
        let segments = session.segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.startTime < $1.startTime }

        if segments.isEmpty {
            return "1\n00:00:00,000 --> 00:00:05,000\n\(session.displayTranscript)\n"
        }

        return segments.enumerated().map { index, segment in
            [
                "\(index + 1)",
                "\(formatSRTTime(segment.startTime)) --> \(formatSRTTime(max(segment.endTime, segment.startTime + 1)))",
                segment.text,
                ""
            ].joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func formatSRTTime(_ time: TimeInterval) -> String {
        let milliseconds = Int((time * 1000).rounded())
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds % 3_600_000) / 60_000
        let seconds = (milliseconds % 60_000) / 1000
        let millis = milliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }
}

struct LiveChunkStats: Hashable {
    var submitted = 0
    var completed = 0
    var failed = 0
}

enum ModelLoadState: Hashable {
    case idle
    case loading(String)
    case ready(String)
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            "Model idle"
        case let .loading(model):
            "Loading \(model)"
        case let .ready(model):
            "\(model) ready"
        case .failed:
            "Model failed"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            "FluidAudio will load the model on first use."
        case .loading:
            "Downloading model files if needed, then warming Core ML."
        case .ready:
            "Loaded locally and ready for recording."
        case let .failed(message):
            message
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

enum TranscriptExportFormat {
    case text
    case json
    case srt

    var fileExtension: String {
        switch self {
        case .text:
            "txt"
        case .json:
            "json"
        case .srt:
            "srt"
        }
    }

    var contentType: UTType {
        switch self {
        case .text:
            .plainText
        case .json:
            .json
        case .srt:
            UTType(filenameExtension: "srt") ?? .plainText
        }
    }
}

private struct TranscriptExportPayload: Encodable {
    let id: UUID
    let createdAt: Date
    let audioPath: String
    let model: String
    let transcript: String
    let liveTranscript: String
    let finalTranscript: String
    let segments: [TranscriptSegment]
    let benchmarks: [TranscriptionBenchmark]
    let duration: TimeInterval?
    let fileSize: Int64?
}
