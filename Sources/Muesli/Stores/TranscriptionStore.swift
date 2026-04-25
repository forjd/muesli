import AppKit
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

    private let recorder = AudioRecorder()
    private let transcriber = ParakeetTranscriber()
    private let persistence = SessionPersistence()
    private var activeRecordingURL: URL?
    private var activeSessionID: TranscriptSession.ID?
    private var meterTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var liveChunkTasks: [Task<Void, Never>] = []

    init() {
        sessions = persistence.load()
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
            let url = try recorder.start(chunkDuration: 4) { [weak self] chunk in
                Task { @MainActor [weak self] in
                    self?.handleLiveChunk(chunk)
                }
            }
            let session = TranscriptSession(audioURL: url, model: selectedModel, status: .recording)
            sessions.insert(session, at: 0)
            selectedSessionID = session.id
            activeSessionID = session.id
            activeRecordingURL = url
            isRecording = true
            statusMessage = "Recording..."
            scheduleSave()
            startMetering()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func stopRecording() -> TranscriptSession.ID? {
        guard isRecording else { return nil }
        recorder.stop()
        liveChunkTasks.forEach { $0.cancel() }
        liveChunkTasks.removeAll()
        meterTask?.cancel()
        currentAudioLevel = -80
        isRecording = false

        if let activeSessionID, sessions.contains(where: { $0.id == activeSessionID }) {
            statusMessage = "Recording saved."
            self.activeRecordingURL = nil
            self.activeSessionID = nil
            if let index = sessions.firstIndex(where: { $0.id == activeSessionID }),
               sessions[index].status == .recording {
                sessions[index].status = .recorded
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
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              sessions[index].status == .recording else {
            return
        }

        isBusy = true
        selectedSessionID = sessionID
        sessions[index].status = .transcribing
        sessions[index].errorMessage = nil
        sessions[index].model = selectedModel
        statusMessage = "Transcribing with \(selectedModel.label)..."
        scheduleSave()

        let audioURL = sessions[index].audioURL
        let model = selectedModel

        do {
            let result = try await transcriber.transcribe(audioURL: audioURL, model: model)
            if let updatedIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
                sessions[updatedIndex].status = .complete
                sessions[updatedIndex].transcript = result.text
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

    private func handleLiveChunk(_ chunk: RecordingChunk) {
        guard isRecording, let activeSessionID else { return }

        let model = selectedModel
        statusMessage = "Transcribing chunk \(chunk.index)..."
        let task = Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await self.transcriber.transcribe(audioURL: chunk.url, model: model)
                await MainActor.run {
                    self.appendLiveTranscript(
                        result.text,
                        sessionID: activeSessionID,
                        chunkIndex: chunk.index
                    )
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "Chunk \(chunk.index) failed: \(error.localizedDescription)"
                }
            }
        }
        liveChunkTasks.append(task)
    }

    private func appendLiveTranscript(_ text: String, sessionID: TranscriptSession.ID, chunkIndex: Int) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if sessions[index].transcript.isEmpty {
                sessions[index].transcript = trimmed
            } else {
                sessions[index].transcript += " " + trimmed
            }
        }

        if isRecording, sessionID == activeSessionID {
            statusMessage = "Live transcript updated from chunk \(chunkIndex)."
        }

        scheduleSave()
    }

    func prepareTranscriber() async {
        guard !isWarmingModel else { return }

        isWarmingModel = true
        let model = selectedModel
        statusMessage = "Warming \(model.label)..."

        do {
            try await transcriber.preload(model: model)
            if selectedModel == model {
                statusMessage = "\(model.label) is ready."
            }
        } catch {
            statusMessage = error.localizedDescription
        }

        isWarmingModel = false
    }

    func copyTranscript(sessionID: TranscriptSession.ID) {
        guard let session = sessions.first(where: { $0.id == sessionID }), !session.transcript.isEmpty else {
            statusMessage = "No transcript to copy."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.transcript, forType: .string)
        statusMessage = "Transcript copied."
    }

    func exportTranscript(sessionID: TranscriptSession.ID, format: TranscriptExportFormat) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        guard !session.transcript.isEmpty else {
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

    private func scheduleSave() {
        let sessions = sessions
        let persistence = persistence
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            try? persistence.save(sessions)
        }
    }

    private func exportFilename(for session: TranscriptSession, format: TranscriptExportFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "muesli-\(formatter.string(from: session.createdAt)).\(format.fileExtension)"
    }

    private func exportData(for session: TranscriptSession, format: TranscriptExportFormat) throws -> Data {
        switch format {
        case .text:
            return Data(session.transcript.utf8)
        case .json:
            let payload = TranscriptExportPayload(
                id: session.id,
                createdAt: session.createdAt,
                audioPath: session.audioURL.path,
                model: session.model.rawValue,
                transcript: session.transcript
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(payload)
        }
    }
}

enum TranscriptExportFormat {
    case text
    case json

    var fileExtension: String {
        switch self {
        case .text:
            "txt"
        case .json:
            "json"
        }
    }

    var contentType: UTType {
        switch self {
        case .text:
            .plainText
        case .json:
            .json
        }
    }
}

private struct TranscriptExportPayload: Encodable {
    let id: UUID
    let createdAt: Date
    let audioPath: String
    let model: String
    let transcript: String
}
