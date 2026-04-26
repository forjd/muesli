import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import OSLog

@MainActor
final class TranscriptionStore: ObservableObject {
    private enum PreferenceKey {
        static let selectedModel = "selectedModel"
        static let autoPasteDictation = "autoPasteDictation"
        static let pasteDelay = "pasteDelay"
        static let deleteAudioAfterTranscription = "deleteAudioAfterTranscription"
        static let retentionPolicy = "retentionPolicy"
        static let dictationHotKey = "dictationHotKey"
        static let dictationHotKeyMode = "dictationHotKeyMode"
    }

    private static let pasteLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.local.Muesli",
        category: "DictationPaste"
    )

    @Published var sessions: [TranscriptSession] = []
    @Published var selectedSessionID: TranscriptSession.ID?
    @Published var isRecording = false
    @Published var isBusy = false
    @Published var currentAudioLevel: Float = -80
    @Published var selectedModel: ParakeetModel = .v3 {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: PreferenceKey.selectedModel)
        }
    }
    @Published var statusMessage = "Ready"
    @Published var isWarmingModel = false
    @Published var modelLoadState: ModelLoadState = .idle
    @Published var recordingElapsed: TimeInterval = 0
    @Published var liveChunkStats: [TranscriptSession.ID: LiveChunkStats] = [:]
    @Published var transcriberHealth: TranscriberHealth?
    @Published var autoPasteDictation = true {
        didSet {
            UserDefaults.standard.set(autoPasteDictation, forKey: PreferenceKey.autoPasteDictation)
        }
    }
    @Published var pasteDelay: TimeInterval = 0.35 {
        didSet {
            pasteDelay = min(max(pasteDelay, 0.1), 2.0)
            UserDefaults.standard.set(pasteDelay, forKey: PreferenceKey.pasteDelay)
        }
    }
    @Published var deleteAudioAfterTranscription = false {
        didSet {
            UserDefaults.standard.set(deleteAudioAfterTranscription, forKey: PreferenceKey.deleteAudioAfterTranscription)
        }
    }
    @Published var retentionPolicy = RetentionPolicy() {
        didSet {
            retentionPolicy.days = RetentionPolicy.clampedDays(retentionPolicy.days)
            if let data = try? JSONEncoder().encode(retentionPolicy) {
                UserDefaults.standard.set(data, forKey: PreferenceKey.retentionPolicy)
            }
            applyRetentionPolicy()
        }
    }
    @Published var dictationHotKey: DictationHotKey = .commandShiftD {
        didSet {
            if let data = try? JSONEncoder().encode(dictationHotKey) {
                UserDefaults.standard.set(data, forKey: PreferenceKey.dictationHotKey)
            }
        }
    }
    @Published var dictationHotKeyMode: DictationHotKeyMode = .hybrid {
        didSet {
            UserDefaults.standard.set(dictationHotKeyMode.rawValue, forKey: PreferenceKey.dictationHotKeyMode)
        }
    }
    @Published private(set) var privacyMode: PrivacyMode = .localOnlyDictation

    private let recorder = AudioRecorder()
    private let transcriber = ParakeetTranscriber()
    private let persistence = SessionPersistence()
    private let secureStorage = SecureStorage()
    private var activeRecordingURL: URL?
    private var activeSessionID: TranscriptSession.ID?
    private var meterTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var failedLiveChunks: [TranscriptSession.ID: [RecordingChunk]] = [:]
    private var liveChunkQueue: Task<Void, Never>?
    private var dictationTargetApp: NSRunningApplication?
    private var dictationTargetElement: AXUIElement?
    private var dictationTargetBundleIdentifier: String?
    private let longRecordingFinalPassLimit: TimeInterval = 30 * 60

    init() {
        let defaults = UserDefaults.standard
        if let modelRawValue = defaults.string(forKey: PreferenceKey.selectedModel),
           let model = ParakeetModel(rawValue: modelRawValue) {
            selectedModel = model
        }
        if defaults.object(forKey: PreferenceKey.autoPasteDictation) != nil {
            autoPasteDictation = defaults.bool(forKey: PreferenceKey.autoPasteDictation)
        }
        if defaults.object(forKey: PreferenceKey.pasteDelay) != nil {
            pasteDelay = min(max(defaults.double(forKey: PreferenceKey.pasteDelay), 0.1), 2.0)
        }
        if defaults.object(forKey: PreferenceKey.deleteAudioAfterTranscription) != nil {
            deleteAudioAfterTranscription = defaults.bool(forKey: PreferenceKey.deleteAudioAfterTranscription)
        }
        if let retentionPolicyData = defaults.data(forKey: PreferenceKey.retentionPolicy),
           let policy = try? JSONDecoder().decode(RetentionPolicy.self, from: retentionPolicyData) {
            retentionPolicy = policy
        }
        if let hotKeyData = defaults.data(forKey: PreferenceKey.dictationHotKey),
           let hotKey = try? JSONDecoder().decode(DictationHotKey.self, from: hotKeyData) {
            dictationHotKey = hotKey
        } else if let legacyHotKeyRawValue = defaults.string(forKey: PreferenceKey.dictationHotKey),
                  let hotKey = DictationHotKey.legacyPreset(rawValue: legacyHotKeyRawValue) {
            dictationHotKey = hotKey
        }
        if let hotKeyModeRawValue = defaults.string(forKey: PreferenceKey.dictationHotKeyMode),
           let hotKeyMode = DictationHotKeyMode(rawValue: hotKeyModeRawValue) {
            dictationHotKeyMode = hotKeyMode
        }

        sessions = persistence.load()
        hydrateRecordingMetadata()
        normalizeInterruptedSessions()
        applyRetentionPolicy()
        selectedSessionID = sessions.first?.id
    }

    var latestRecordingURL: URL? {
        activeRecordingURL ?? sessions.first?.audioURL
    }

    var selectedSession: TranscriptSession? {
        guard let selectedSessionID else { return sessions.first }
        return sessions.first { $0.id == selectedSessionID }
    }

    var recordingsDirectoryURL: URL {
        persistence.recordingsDirectory
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

    func toggleDictationPaste() async {
        if isRecording {
            await finishDictationPaste()
        } else {
            await startDictationPaste()
        }
    }

    func startDictationPaste() async {
        guard !isRecording else { return }
        dictationTargetApp = NSWorkspace.shared.frontmostApplication
        dictationTargetBundleIdentifier = dictationTargetApp?.bundleIdentifier
        dictationTargetElement = Self.focusedAccessibilityElement()
        let targetName = dictationTargetApp?.localizedName ?? "nil"
        let targetBundle = dictationTargetBundleIdentifier ?? "nil"
        let elementSummary = Self.describeAccessibilityElement(dictationTargetElement)
        Self.pasteLogger.info("Dictation hotkey start target=\(targetName, privacy: .public) bundle=\(targetBundle, privacy: .public) axElement=\(elementSummary, privacy: .public)")
        await startRecording()
        if isRecording {
            statusMessage = "Dictation recording; press \(dictationHotKey.label) to paste."
        }
    }

    func finishDictationPaste() async {
        guard isRecording else { return }
        Self.pasteLogger.info("Dictation hotkey stop requested")
        guard let sessionID = stopRecording() else { return }
        await transcribe(sessionID: sessionID)
        pasteTranscript(sessionID: sessionID)
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

        let model = selectedModel

        if let duration = sessions[index].duration,
           duration > longRecordingFinalPassLimit,
           !sessions[index].liveTranscript.isEmpty {
            sessions[index].status = .complete
            sessions[index].transcript = sessions[index].liveTranscript
            sessions[index].finalTranscript = ""
            if deleteAudioAfterTranscription {
                deleteAudioFile(for: sessions[index])
                updateRecordingMetadata(at: index)
            } else {
                encryptAudioFileIfNeeded(at: index)
            }
            deleteChunkFiles(for: sessions[index])
            statusMessage = "Skipped final pass for long recording; using live transcript."
            isBusy = false
            scheduleSave()
            return
        }

        do {
            let storedAudioURL = sessions[index].audioURL
            let transcriptionAudioURL = try temporaryReadableAudioURL(for: sessions[index])
            defer {
                if transcriptionAudioURL != storedAudioURL {
                    try? FileManager.default.removeItem(at: transcriptionAudioURL)
                }
            }

            let result = try await transcriber.transcribe(audioURL: transcriptionAudioURL, model: model)
            if let updatedIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
                sessions[updatedIndex].status = .complete
                let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                sessions[updatedIndex].finalTranscript = trimmed
                if !trimmed.isEmpty {
                    sessions[updatedIndex].transcript = trimmed
                } else if !sessions[updatedIndex].liveTranscript.isEmpty {
                    sessions[updatedIndex].transcript = sessions[updatedIndex].liveTranscript
                }
                if deleteAudioAfterTranscription {
                    deleteAudioFile(for: sessions[updatedIndex])
                    updateRecordingMetadata(at: updatedIndex)
                } else {
                    encryptAudioFileIfNeeded(at: updatedIndex)
                }
                deleteChunkFiles(for: sessions[updatedIndex])
            }
            if statusMessage.hasPrefix("Transcription complete, but audio encryption failed") == false {
                statusMessage = "Transcription complete."
            }
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
        if !sessions[index].isAudioEncrypted,
           let audioFile = try? AVAudioFile(forReading: url),
           audioFile.processingFormat.sampleRate > 0 {
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
        let isCached = await transcriber.isModelCached(model)
        modelLoadState = isCached ? .loadingCached(model.label) : .downloading(model.label)
        statusMessage = isCached ? "Loading cached \(model.label)..." : "Downloading \(model.label)..."

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

    private func pasteTranscript(sessionID: TranscriptSession.ID) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        let text = session.displayTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            Self.pasteLogger.warning("Paste aborted: transcript empty for session \(sessionID.uuidString, privacy: .public)")
            statusMessage = "No transcript to paste."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Self.pasteLogger.info("Paste pipeline copied transcript chars=\(text.count, privacy: .public)")

        let isTrusted = AXIsProcessTrusted()
        Self.pasteLogger.info("Accessibility trusted=\(isTrusted, privacy: .public)")
        guard autoPasteDictation else {
            dictationTargetApp = nil
            dictationTargetElement = nil
            dictationTargetBundleIdentifier = nil
            statusMessage = "Copied transcript. Auto-paste is off."
            return
        }

        guard isTrusted else {
            dictationTargetApp = nil
            dictationTargetElement = nil
            dictationTargetBundleIdentifier = nil
            statusMessage = "Copied transcript. Re-enable Muesli in Accessibility if auto-paste does not work."
            return
        }

        let target = dictationTargetApp
        let targetElement = dictationTargetElement
        let targetBundleIdentifier = dictationTargetBundleIdentifier
        dictationTargetApp = nil
        dictationTargetElement = nil
        dictationTargetBundleIdentifier = nil
        target?.activate(options: [.activateAllWindows])
        Self.pasteLogger.info("Paste target app=\(target?.localizedName ?? "nil", privacy: .public) bundle=\(targetBundleIdentifier ?? "nil", privacy: .public) pid=\(target?.processIdentifier ?? -1, privacy: .public) capturedAX=\(Self.describeAccessibilityElement(targetElement), privacy: .public)")

        statusMessage = "Copied transcript; attempting paste into \(target?.localizedName ?? "front app")..."
        let pasteDelay = pasteDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) { [weak self] in
            if let processIdentifier = target?.processIdentifier {
                Self.pasteLogger.info("Posting single Command-V to pid=\(processIdentifier, privacy: .public)")
                Self.postPasteShortcut(to: processIdentifier)
            } else {
                Self.pasteLogger.info("Posting single Command-V to session event tap")
                Self.postPasteShortcutToSession()
            }

            Task { @MainActor in
                self?.statusMessage = "Copied transcript and sent paste shortcut."
            }
        }
    }

    func openRecordingsFolder() {
        try? FileManager.default.createDirectory(at: recordingsDirectoryURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(recordingsDirectoryURL)
    }

    private static func focusedAccessibilityElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedError == .success, let focusedValue else { return nil }
        return (focusedValue as! AXUIElement)
    }

    private static func describeAccessibilityElement(_ element: AXUIElement?) -> String {
        guard let element else { return "nil" }
        let role = accessibilityStringAttribute(kAXRoleAttribute, from: element) ?? "unknown"
        let subrole = accessibilityStringAttribute(kAXSubroleAttribute, from: element) ?? "none"
        let title = accessibilityStringAttribute(kAXTitleAttribute, from: element) ?? "none"
        let hasValue = accessibilityStringAttribute(kAXValueAttribute, from: element) != nil
        var valueSettable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueSettable)
        var selectedTextSettable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &selectedTextSettable)
        return "role=\(role) subrole=\(subrole) title=\(title) hasValue=\(hasValue) valueSettable=\(valueSettable.boolValue) selectedTextSettable=\(selectedTextSettable.boolValue)"
    }

    private static func insertTextWithAccessibility(_ text: String, into element: AXUIElement?) -> PasteAttemptResult {
        guard let element else {
            return PasteAttemptResult(succeeded: false, detail: "no focused element")
        }

        let role = accessibilityStringAttribute(kAXRoleAttribute, from: element) ?? "unknown role"
        var valueRef: CFTypeRef?
        let valueReadError = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        let currentText = valueRef as? String

        var valueSettable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueSettable)
        if valueReadError == .success, let currentText, valueSettable.boolValue {
            var selectedRange = CFRange(location: currentText.utf16.count, length: 0)
            var selectedRangeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success,
               let selectedRangeRef,
               CFGetTypeID(selectedRangeRef) == AXValueGetTypeID(),
               AXValueGetType(selectedRangeRef as! AXValue) == .cfRange {
                AXValueGetValue(selectedRangeRef as! AXValue, .cfRange, &selectedRange)
            }

            let lowerBound = max(0, min(selectedRange.location, currentText.utf16.count))
            let upperBound = max(lowerBound, min(selectedRange.location + selectedRange.length, currentText.utf16.count))
            let start = String.Index(utf16Offset: lowerBound, in: currentText)
            let end = String.Index(utf16Offset: upperBound, in: currentText)

            var updatedText = currentText
            updatedText.replaceSubrange(start..<end, with: text)
            let setValueError = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, updatedText as CFString)
            guard setValueError == .success else {
                return PasteAttemptResult(succeeded: false, detail: "\(role) rejected AXValue error=\(setValueError.rawValue)")
            }

            var readbackRef: CFTypeRef?
            let readbackError = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &readbackRef)
            guard readbackError == .success, readbackRef as? String == updatedText else {
                return PasteAttemptResult(succeeded: false, detail: "\(role) AXValue set did not stick readback=\(readbackError.rawValue)")
            }

            var insertionRange = CFRange(location: lowerBound + text.utf16.count, length: 0)
            if let insertionValue = AXValueCreate(.cfRange, &insertionRange) {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, insertionValue)
            }

            return PasteAttemptResult(succeeded: true, detail: "set value on \(role) at \(lowerBound) replacing \(upperBound - lowerBound)")
        }

        var selectedTextSettable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &selectedTextSettable)
        if selectedTextSettable.boolValue {
            let selectedTextError = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            if selectedTextError == .success {
                return PasteAttemptResult(succeeded: false, detail: "selected text accepted but AXValue unavailable; falling back")
            }
            return PasteAttemptResult(succeeded: false, detail: "\(role) selected text rejected error=\(selectedTextError.rawValue)")
        }

        if valueReadError != .success || currentText == nil {
            return PasteAttemptResult(succeeded: false, detail: "\(role) value unreadable error=\(valueReadError.rawValue)")
        }
        return PasteAttemptResult(succeeded: false, detail: "\(role) value is not settable")
    }

    private static func accessibilityStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func makePasteEvents() -> [CGEvent] {
        let source = CGEventSource(stateID: .combinedSessionState)
        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

        commandDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        commandUp?.flags = []

        return [commandDown, vDown, vUp, commandUp].compactMap(\.self)
    }

    private static func postPasteShortcut(to processIdentifier: pid_t) {
        pasteLogger.debug("postPasteShortcut(to:) events=\(makePasteEvents().count, privacy: .public)")
        makePasteEvents().forEach { event in
            event.postToPid(processIdentifier)
        }
    }

    private static func postPasteShortcutToSession() {
        pasteLogger.debug("postPasteShortcutToSession events=\(makePasteEvents().count, privacy: .public)")
        makePasteEvents().forEach { event in
            event.post(tap: .cgSessionEventTap)
        }
    }

    private static func postUnicodeText(_ text: String, to processIdentifier: pid_t) {
        pasteLogger.debug("postUnicodeText(to:) utf16Count=\(text.utf16.count, privacy: .public)")
        makeUnicodeEvents(for: text).forEach { event in
            event.postToPid(processIdentifier)
        }
    }

    private static func postUnicodeTextToSession(_ text: String) {
        pasteLogger.debug("postUnicodeTextToSession utf16Count=\(text.utf16.count, privacy: .public)")
        makeUnicodeEvents(for: text).forEach { event in
            event.post(tap: .cgSessionEventTap)
        }
    }

    private static func makeUnicodeEvents(for text: String) -> [CGEvent] {
        let source = CGEventSource(stateID: .combinedSessionState)
        return text.utf16.flatMap { codeUnit -> [CGEvent] in
            var character = codeUnit
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character)

            var keyUpCharacter = codeUnit
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &keyUpCharacter)

            return [keyDown, keyUp].compactMap(\.self)
        }
    }

    private static func postPasteWithSystemEvents(targetBundleIdentifier: String?) -> String? {
        var script = ""
        if let targetBundleIdentifier, !targetBundleIdentifier.isEmpty {
            script += #"tell application id "\#(targetBundleIdentifier)" to activate"# + "\n"
            script += "delay 0.3\n"
        }
        script += #"tell application "System Events" to keystroke "v" using command down"#
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            pasteLogger.error("AppleScript error number=\((error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0, privacy: .public) message=\((error[NSAppleScript.errorMessage] as? String) ?? "unknown", privacy: .public)")
        }
        return error?[NSAppleScript.errorMessage] as? String
    }

    func updateTranscript(sessionID: TranscriptSession.ID, text: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if !sessions[index].finalTranscript.isEmpty {
            sessions[index].finalTranscript = trimmed
        } else if !sessions[index].liveTranscript.isEmpty {
            sessions[index].liveTranscript = trimmed
        }

        sessions[index].transcript = trimmed
        statusMessage = "Transcript updated."
        scheduleSave()
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

    func deleteAllSessions() {
        if isRecording {
            recorder.stop()
            liveChunkQueue?.cancel()
            liveChunkQueue = nil
            meterTask?.cancel()
            elapsedTask?.cancel()
            currentAudioLevel = -80
            recordingElapsed = 0
            isRecording = false
            activeRecordingURL = nil
            activeSessionID = nil
        }

        sessions.forEach(deleteFiles)
        sessions.removeAll()
        selectedSessionID = nil
        liveChunkStats.removeAll()
        failedLiveChunks.removeAll()
        dictationTargetApp = nil
        dictationTargetElement = nil
        dictationTargetBundleIdentifier = nil
        statusMessage = "Deleted all recordings and transcripts."
        scheduleSave()
    }

    func applyRetentionPolicy(now: Date = Date()) {
        guard retentionPolicy.isEnabled, !sessions.isEmpty else { return }

        var changed = false
        var retainedSessions: [TranscriptSession] = []

        for var session in sessions {
            guard retentionPolicy.isExpired(session, now: now) else {
                retainedSessions.append(session)
                continue
            }

            switch retentionPolicy.target {
            case .off:
                retainedSessions.append(session)
            case .recordings:
                deleteAudioFile(for: session)
                deleteChunkFiles(for: session)
                if session.fileSize != nil || session.duration != nil || session.isAudioEncrypted {
                    session.fileSize = nil
                    session.duration = nil
                    session.isAudioEncrypted = false
                }
                retainedSessions.append(session)
                changed = true
            case .transcripts:
                if !session.transcript.isEmpty || !session.liveTranscript.isEmpty || !session.finalTranscript.isEmpty || !session.segments.isEmpty {
                    session.transcript = ""
                    session.liveTranscript = ""
                    session.finalTranscript = ""
                    session.segments = []
                    changed = true
                }
                retainedSessions.append(session)
            case .recordingsAndTranscripts:
                deleteFiles(for: session)
                liveChunkStats[session.id] = nil
                failedLiveChunks[session.id] = nil
                changed = true
            }
        }

        guard changed else { return }

        sessions = retainedSessions
        if let selectedSessionID, !sessions.contains(where: { $0.id == selectedSessionID }) {
            self.selectedSessionID = sessions.first?.id
        }
        statusMessage = "Applied retention policy."
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
        deleteAudioFile(for: session)
        deleteChunkFiles(for: session)
    }

    private func deleteChunkFiles(for session: TranscriptSession) {
        let fileManager = FileManager.default
        let chunkDirectory = session.audioURL
            .deletingLastPathComponent()
            .appending(path: "Chunks", directoryHint: .isDirectory)
            .appending(path: session.audioURL.deletingPathExtension().lastPathComponent, directoryHint: .isDirectory)
        try? fileManager.removeItem(at: chunkDirectory)
    }

    private func deleteAudioFile(for session: TranscriptSession) {
        try? FileManager.default.removeItem(at: session.audioURL)
    }

    private func temporaryReadableAudioURL(for session: TranscriptSession) throws -> URL {
        guard session.isAudioEncrypted else {
            return session.audioURL
        }
        return try secureStorage.decryptedTemporaryFile(from: session.audioURL)
    }

    private func encryptAudioFileIfNeeded(at index: Int) {
        guard !sessions[index].isAudioEncrypted else { return }

        do {
            try secureStorage.encryptFile(at: sessions[index].audioURL)
            sessions[index].isAudioEncrypted = true
            updateRecordingMetadata(at: index)
        } catch {
            sessions[index].errorMessage = error.localizedDescription
            statusMessage = "Transcription complete, but audio encryption failed: \(error.localizedDescription)"
        }
    }

    private func exportFilename(for session: TranscriptSession, format: TranscriptExportFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "muesli-\(formatter.string(from: session.createdAt)).\(format.fileExtension)"
    }

    private func exportData(for session: TranscriptSession, format: TranscriptExportFormat) throws -> Data {
        try TranscriptExporter.data(for: session, format: format)
    }
}

struct LiveChunkStats: Hashable {
    var submitted = 0
    var completed = 0
    var failed = 0
}

private struct PasteAttemptResult {
    let succeeded: Bool
    let detail: String
}

enum ModelLoadState: Hashable {
    case idle
    case loadingCached(String)
    case downloading(String)
    case ready(String)
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            "Model idle"
        case let .loadingCached(model):
            "Loading \(model)"
        case let .downloading(model):
            "Downloading \(model)"
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
        case .loadingCached:
            "Using cached model files and warming Core ML."
        case .downloading:
            "Fetching model files once, then warming Core ML."
        case .ready:
            "Loaded locally and ready for recording."
        case let .failed(message):
            message
        }
    }

    var isLoading: Bool {
        switch self {
        case .loadingCached, .downloading:
            true
        default:
            false
        }
    }

    var isReady: Bool {
        switch self {
        case .ready:
            true
        default:
            false
        }
    }
}
