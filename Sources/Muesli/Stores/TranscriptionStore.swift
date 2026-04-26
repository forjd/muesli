import AppKit
import ApplicationServices
import AudioToolbox
import AVFoundation
import Foundation
import OSLog
import UserNotifications

@MainActor
final class TranscriptionStore: ObservableObject {
    private enum PreferenceKey {
        static let selectedModel = "selectedModel"
        static let autoPasteDictation = "autoPasteDictation"
        static let pasteDelay = "pasteDelay"
        static let deleteAudioAfterTranscription = "deleteAudioAfterTranscription"
        static let dictationStorageMode = "dictationStorageMode"
        static let offlineMode = "offlineMode"
        static let soundEffectsEnabled = "soundEffectsEnabled"
        static let replacementRules = "replacementRules"
        static let customDictionaryTerms = "customDictionaryTerms"
        static let customDictionaryProfiles = "customDictionaryProfiles"
        static let selectedCustomDictionaryProfileID = "selectedCustomDictionaryProfileID"
        static let finalPassVocabularyBoostingEnabled = "finalPassVocabularyBoostingEnabled"
        static let retentionPolicy = "retentionPolicy"
        static let dictationHotKey = "dictationHotKey"
        static let dictationHotKeyMode = "dictationHotKeyMode"
        static let recordingOverlayAnchor = "recordingOverlayAnchor"
    }

    private static let pasteLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.local.Muesli",
        category: "DictationPaste"
    )

    @Published var sessions: [TranscriptSession] = []
    @Published var selectedSessionID: TranscriptSession.ID?
    @Published var sessionSearchText = ""
    @Published var sessionStatusFilter: TranscriptStatusFilter = .all
    @Published var isRecording = false
    @Published var isBusy = false
    @Published var currentAudioLevel: Float = -80
    @Published var selectedModel: ParakeetModel = .v3 {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: PreferenceKey.selectedModel)
        }
    }
    @Published var statusMessage = "Ready"
    @Published var activeIssue: AppIssue?
    @Published var latestFeedbackEvent: DictationFeedbackEvent?
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
    @Published var dictationStorageMode: DictationStorageMode = .saveRecordingAndTranscript {
        didSet {
            UserDefaults.standard.set(dictationStorageMode.rawValue, forKey: PreferenceKey.dictationStorageMode)
        }
    }
    @Published var offlineMode = false {
        didSet {
            UserDefaults.standard.set(offlineMode, forKey: PreferenceKey.offlineMode)
            if offlineMode {
                Task { await prepareTranscriber() }
            }
        }
    }
    @Published var soundEffectsEnabled = false {
        didSet {
            UserDefaults.standard.set(soundEffectsEnabled, forKey: PreferenceKey.soundEffectsEnabled)
        }
    }
    @Published var replacementRules: [ReplacementRule] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(replacementRules) {
                UserDefaults.standard.set(data, forKey: PreferenceKey.replacementRules)
            }
        }
    }
    @Published var customDictionaryProfiles: [CustomDictionaryProfile] = CustomDictionaryProfile.defaultProfiles {
        didSet {
            if let data = try? JSONEncoder().encode(customDictionaryProfiles) {
                UserDefaults.standard.set(data, forKey: PreferenceKey.customDictionaryProfiles)
            }
        }
    }
    @Published var selectedCustomDictionaryProfileID: CustomDictionaryProfile.ID = CustomDictionaryProfile.generalID {
        didSet {
            UserDefaults.standard.set(selectedCustomDictionaryProfileID.uuidString, forKey: PreferenceKey.selectedCustomDictionaryProfileID)
        }
    }
    @Published var finalPassVocabularyBoostingEnabled = false {
        didSet {
            UserDefaults.standard.set(finalPassVocabularyBoostingEnabled, forKey: PreferenceKey.finalPassVocabularyBoostingEnabled)
        }
    }
    @Published var fuzzyDictionarySuggestions: [FuzzyDictionarySuggestion] = []
    @Published var lastManualReplacementSuggestion: ReplacementRule?
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
    @Published var recordingOverlayAnchor: RecordingOverlayAnchor = .top {
        didSet {
            UserDefaults.standard.set(recordingOverlayAnchor.rawValue, forKey: PreferenceKey.recordingOverlayAnchor)
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
    private var dictationSessionID: TranscriptSession.ID?
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
        if let dictationStorageModeRawValue = defaults.string(forKey: PreferenceKey.dictationStorageMode),
           let mode = DictationStorageMode(rawValue: dictationStorageModeRawValue) {
            dictationStorageMode = mode
        }
        if defaults.object(forKey: PreferenceKey.offlineMode) != nil {
            offlineMode = defaults.bool(forKey: PreferenceKey.offlineMode)
        }
        if defaults.object(forKey: PreferenceKey.soundEffectsEnabled) != nil {
            soundEffectsEnabled = defaults.bool(forKey: PreferenceKey.soundEffectsEnabled)
        }
        if let replacementRulesData = defaults.data(forKey: PreferenceKey.replacementRules),
           let rules = try? JSONDecoder().decode([ReplacementRule].self, from: replacementRulesData) {
            replacementRules = rules
        }
        if let profilesData = defaults.data(forKey: PreferenceKey.customDictionaryProfiles),
           let profiles = try? JSONDecoder().decode([CustomDictionaryProfile].self, from: profilesData),
           !profiles.isEmpty {
            customDictionaryProfiles = profiles
        } else if let dictionaryData = defaults.data(forKey: PreferenceKey.customDictionaryTerms),
                  let terms = try? JSONDecoder().decode([CustomDictionaryTerm].self, from: dictionaryData),
                  !terms.isEmpty {
            customDictionaryProfiles = CustomDictionaryProfile.defaultProfiles
            if let generalIndex = customDictionaryProfiles.firstIndex(where: { $0.id == CustomDictionaryProfile.generalID }) {
                customDictionaryProfiles[generalIndex].terms = terms
            }
        }
        if let selectedProfileIDString = defaults.string(forKey: PreferenceKey.selectedCustomDictionaryProfileID),
           let selectedProfileID = UUID(uuidString: selectedProfileIDString),
           customDictionaryProfiles.contains(where: { $0.id == selectedProfileID }) {
            selectedCustomDictionaryProfileID = selectedProfileID
        } else if let firstProfileID = customDictionaryProfiles.first?.id {
            selectedCustomDictionaryProfileID = firstProfileID
        }
        if defaults.object(forKey: PreferenceKey.finalPassVocabularyBoostingEnabled) != nil {
            finalPassVocabularyBoostingEnabled = defaults.bool(forKey: PreferenceKey.finalPassVocabularyBoostingEnabled)
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
        if let overlayAnchorRawValue = defaults.string(forKey: PreferenceKey.recordingOverlayAnchor),
           let overlayAnchor = RecordingOverlayAnchor(rawValue: overlayAnchorRawValue) {
            recordingOverlayAnchor = overlayAnchor
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

    var filteredSessions: [TranscriptSession] {
        TranscriptSessionFilter(searchText: sessionSearchText, status: sessionStatusFilter)
            .apply(to: sessions)
    }

    var recordingsDirectoryURL: URL {
        persistence.recordingsDirectory
    }

    func importAudioFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = AudioImportFormat.contentTypes
        panel.message = "Choose an audio file to copy into Muesli and transcribe."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            await importAudioFile(at: url, transcribeAfterImport: true)
        }
    }

    func batchImportAudioFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = AudioImportFormat.contentTypes
        panel.message = "Choose audio files to copy into Muesli and transcribe."

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        Task {
            await importAudioFiles(at: panel.urls, transcribeAfterImport: true)
        }
    }

    func importAudioFiles(at sourceURLs: [URL], transcribeAfterImport: Bool = false) async {
        guard !isBusy, !isRecording else { return }
        guard !sourceURLs.isEmpty else { return }

        var importedIDs: [TranscriptSession.ID] = []
        var failures: [String] = []

        isBusy = true
        for (offset, sourceURL) in sourceURLs.enumerated() {
            statusMessage = "Importing \(offset + 1) of \(sourceURLs.count)..."
            guard AudioImportFormat.isSupported(sourceURL) else {
                failures.append("\(sourceURL.lastPathComponent): unsupported format")
                continue
            }

            do {
                let importedURL = try copyImportedAudio(from: sourceURL)
                let session = TranscriptSession(audioURL: importedURL, model: selectedModel, status: .recorded)
                sessions.insert(session, at: 0)
                selectedSessionID = session.id
                updateRecordingMetadata(at: 0)
                importedIDs.append(session.id)
                scheduleSave()
            } catch {
                failures.append("\(sourceURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        isBusy = false

        if transcribeAfterImport {
            for (offset, sessionID) in importedIDs.enumerated() {
                statusMessage = "Transcribing import \(offset + 1) of \(importedIDs.count)..."
                await transcribe(sessionID: sessionID)
            }
        }

        if failures.isEmpty {
            statusMessage = "Imported \(importedIDs.count) audio file\(importedIDs.count == 1 ? "" : "s")."
        } else {
            statusMessage = "Imported \(importedIDs.count); \(failures.count) failed. \(failures.prefix(2).joined(separator: " "))"
        }
    }

    func importAudioFile(at sourceURL: URL, transcribeAfterImport: Bool = false) async {
        guard !isBusy, !isRecording else { return }
        guard AudioImportFormat.isSupported(sourceURL) else {
            statusMessage = "Unsupported audio format. Import WAV, M4A, MP3, AIFF, or CAF."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let importedURL = try copyImportedAudio(from: sourceURL)
            var session = TranscriptSession(audioURL: importedURL, model: selectedModel, status: .recorded)
            sessions.insert(session, at: 0)
            selectedSessionID = session.id
            updateRecordingMetadata(at: 0)
            session = sessions[0]
            statusMessage = "Imported \(sourceURL.lastPathComponent)."
            scheduleSave()

            if transcribeAfterImport {
                isBusy = false
                await transcribe(sessionID: session.id)
            }
        } catch {
            statusMessage = error.localizedDescription
        }
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
            activeIssue = AppIssue(
                kind: .microphonePermission,
                detail: "Allow microphone access in System Settings, then return to Muesli and start recording again."
            )
            return
        }
        guard await selectedModelIsAvailable() else {
            return
        }

        do {
            let sessionID = TranscriptSession.ID()
            let url = try recorder.start(vadConfiguration: VoiceActivityChunkRotation.Configuration()) { [weak self] chunk in
                Task { @MainActor [weak self] in
                    self?.handleLiveChunk(chunk, sessionID: sessionID)
                }
            }
            let session = TranscriptSession(id: sessionID, audioURL: url, model: selectedModel, status: .recording)
            sessions.insert(session, at: 0)
            selectedSessionID = session.id
            activeSessionID = session.id
            liveChunkStats[session.id] = LiveChunkStats()
            activeRecordingURL = url
            isRecording = true
            publishFeedback(title: "Recording Started", detail: "Listening for dictation.", kind: .recordingStarted)
            try await transcriber.startStreaming(sessionID: session.id, model: selectedModel)
            scheduleSave()
            startMetering()
            startElapsedTimer()
            activeIssue = nil
        } catch {
            statusMessage = error.localizedDescription
            activeIssue = AppIssue(
                kind: .microphonePermission,
                detail: "Muesli could not start the microphone input: \(error.localizedDescription)"
            )
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
            publishFeedback(title: "Recording Stopped", detail: "Finalizing audio before transcription.", kind: .recordingStopped)
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
        dictationSessionID = nil
        let targetName = dictationTargetApp?.localizedName ?? "nil"
        let targetBundle = dictationTargetBundleIdentifier ?? "nil"
        let elementSummary = Self.describeAccessibilityElement(dictationTargetElement)
        Self.pasteLogger.info("Dictation hotkey start target=\(targetName, privacy: .public) bundle=\(targetBundle, privacy: .public) axElement=\(elementSummary, privacy: .public)")
        await startRecording()
        if isRecording {
            dictationSessionID = activeSessionID
            statusMessage = "Dictation recording; press \(dictationHotKey.label) to paste."
        }
    }

    func finishDictationPaste() async {
        guard isRecording else { return }
        Self.pasteLogger.info("Dictation hotkey stop requested")
        guard let sessionID = stopRecording() else { return }
        await transcribe(sessionID: sessionID)
        pasteTranscript(sessionID: sessionID)
        finalizeDictationStorage(sessionID: sessionID)
    }

    func cancelDictation() {
        guard isRecording, let activeSessionID else { return }
        recorder.stop()
        liveChunkQueue?.cancel()
        liveChunkQueue = nil
        meterTask?.cancel()
        elapsedTask?.cancel()
        currentAudioLevel = -80
        recordingElapsed = 0
        isRecording = false
        activeRecordingURL = nil
        self.activeSessionID = nil

        if dictationSessionID == activeSessionID {
            deleteSession(sessionID: activeSessionID)
            publishFeedback(title: "Recording Cancelled", detail: "Dictation cancelled and temporary audio deleted.", kind: .failed)
        } else if let index = sessions.firstIndex(where: { $0.id == activeSessionID }) {
            sessions[index].status = .recorded
            updateRecordingMetadata(at: index)
            statusMessage = "Recording cancelled."
            playFeedbackSound(for: .failed)
            scheduleSave()
        }
        dictationSessionID = nil
        dictationTargetApp = nil
        dictationTargetElement = nil
        dictationTargetBundleIdentifier = nil
    }

    func transcribe(sessionID: TranscriptSession.ID) async {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        isBusy = true
        selectedSessionID = sessionID
        guard await selectedModelIsAvailable() else {
            isBusy = false
            return
        }
        sessions[index].status = .transcribing
        sessions[index].errorMessage = nil
        sessions[index].model = selectedModel
        updateRecordingMetadata(at: index)
        statusMessage = "Transcribing with \(selectedModel.label)..."
        latestFeedbackEvent = DictationFeedbackEvent(title: "Transcribing", detail: "Converting speech with \(selectedModel.label).", kind: .transcribing)
        playFeedbackSound(for: .transcribing)
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
            updateFuzzyDictionarySuggestions(for: sessions[index])
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

            let vocabularyBoostingRequest = finalPassVocabularyBoostingRequest()
            let result = try await transcriber.transcribe(
                audioURL: transcriptionAudioURL,
                model: model,
                vocabularyBoosting: vocabularyBoostingRequest
            )
            if let updatedIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
                sessions[updatedIndex].status = .complete
                let trimmed = applyReplacementRules(to: result.text.trimmingCharacters(in: .whitespacesAndNewlines))
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
                updateFuzzyDictionarySuggestions(for: sessions[updatedIndex])
            }
            if statusMessage.hasPrefix("Transcription complete, but audio encryption failed") == false {
                let fuzzySuggestionCount = fuzzyDictionarySuggestions(for: sessionID).count
                if fuzzySuggestionCount > 0 {
                    statusMessage = "Review \(fuzzySuggestionCount) fuzzy dictionary suggestion\(fuzzySuggestionCount == 1 ? "" : "s")."
                } else if let vocabularyBoosting = result.vocabularyBoosting,
                   vocabularyBoosting.status != .skipped || !vocabularyBoosting.detectedTerms.isEmpty {
                    statusMessage = vocabularyBoosting.message
                } else {
                    statusMessage = "Transcription complete."
                }
            }
        } catch {
            if let updatedIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
                sessions[updatedIndex].status = .failed
                sessions[updatedIndex].errorMessage = error.localizedDescription
            }
            statusMessage = error.localizedDescription
            publishFeedback(title: "Transcription Failed", detail: error.localizedDescription, kind: .failed)
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

    private func handleLiveChunk(_ chunk: RecordingChunk, sessionID: TranscriptSession.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        let model = sessions[index].model
        liveChunkStats[sessionID, default: LiveChunkStats()].submitted += 1
        if isRecording, sessionID == activeSessionID {
            statusMessage = "Transcribing chunk \(chunk.index)..."
        }
        let previousTask = liveChunkQueue
        liveChunkQueue = Task { [weak self] in
            await previousTask?.value
            guard let self else { return }

            do {
                if let result = try await self.transcriber.streamChunk(sessionID: sessionID, chunkURL: chunk.url, model: model) {
                    await MainActor.run {
                        self.replaceLiveTranscript(
                            result,
                            sessionID: sessionID,
                            chunkIndex: chunk.index
                        )
                    }
                } else {
                    await MainActor.run {
                        self.liveChunkStats[sessionID, default: LiveChunkStats()].completed += 1
                    }
                }
            } catch {
                await MainActor.run {
                    self.failedLiveChunks[sessionID, default: []].append(chunk)
                    self.liveChunkStats[sessionID, default: LiveChunkStats()].failed += 1
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
        if offlineMode && !isCached {
            modelLoadState = .downloadRequired(model.label)
            statusMessage = "Offline mode is on. Connect once or turn off offline mode to download \(model.label)."
            isWarmingModel = false
            return
        }
        modelLoadState = isCached ? .loadingCached(model.label) : .downloading(model.label)
        statusMessage = isCached ? "Loading cached \(model.label)..." : "Downloading \(model.label)..."

        do {
            try await transcriber.preload(model: model)
            if selectedModel == model {
                modelLoadState = .ready(model.label)
                statusMessage = "\(model.label) is ready."
                activeIssue = nil
            }
        } catch {
            modelLoadState = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
            activeIssue = AppIssue(
                kind: .modelLoad,
                detail: "The selected model could not be prepared: \(error.localizedDescription)"
            )
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

    private func selectedModelIsAvailable() async -> Bool {
        guard offlineMode else { return true }
        let model = selectedModel
        guard await transcriber.isModelCached(model) else {
            modelLoadState = .downloadRequired(model.label)
            statusMessage = "Offline mode is on. \(model.label) must be downloaded before recording or transcription."
            return false
        }
        return true
    }

    func copyTranscript(sessionID: TranscriptSession.ID, template: TranscriptClipboardTemplate = .plain) {
        guard let session = sessions.first(where: { $0.id == sessionID }), !session.transcript.isEmpty else {
            statusMessage = "No transcript to copy."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TranscriptExporter.clipboardText(for: session, template: template), forType: .string)
        statusMessage = "\(template.label) copied."
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
            activeIssue = AppIssue(
                kind: .accessibilityPermission,
                detail: "Muesli copied the transcript, but macOS Accessibility permission is required to paste into another app."
            )
            latestFeedbackEvent = DictationFeedbackEvent(title: "Paste Blocked", detail: "Transcript copied; Accessibility permission is needed to paste.", kind: .failed)
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
                self?.publishFeedback(title: "Dictation Pasted", detail: "Sent paste shortcut to the target app.", kind: .pasted)
            }
        }
    }

    private func publishFeedback(title: String, detail: String, kind: DictationFeedbackKind) {
        statusMessage = detail
        latestFeedbackEvent = DictationFeedbackEvent(title: title, detail: detail, kind: kind)
        playFeedbackSound(for: kind)

        guard !NSApp.isActive, Self.canDeliverUserNotifications else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert])
            }
            let refreshedSettings = await center.notificationSettings()
            guard refreshedSettings.authorizationStatus == .authorized || refreshedSettings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = detail
            let request = UNNotificationRequest(identifier: "muesli.dictation.\(UUID().uuidString)", content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    private static var canDeliverUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private func playFeedbackSound(for kind: DictationFeedbackKind) {
        guard soundEffectsEnabled else { return }
        AudioServicesPlaySystemSound(kind.systemSoundID)
    }

    func reportHotKeyUnavailable(_ detail: String) {
        statusMessage = detail
        activeIssue = AppIssue(kind: .hotKey, detail: detail)
    }

    func dismissIssue() {
        activeIssue = nil
    }

    func openMicrophoneSettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func openAccessibilitySettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openRecordingsFolder() {
        try? FileManager.default.createDirectory(at: recordingsDirectoryURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(recordingsDirectoryURL)
    }

    private func openSettingsPane(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
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
        let previous = sessions[index].displayTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        if !sessions[index].finalTranscript.isEmpty {
            sessions[index].finalTranscript = trimmed
        } else if !sessions[index].liveTranscript.isEmpty {
            sessions[index].liveTranscript = trimmed
        }

        sessions[index].transcript = trimmed
        if !previous.isEmpty, !trimmed.isEmpty, previous != trimmed {
            lastManualReplacementSuggestion = ReplacementRule(find: previous, replace: trimmed, isEnabled: false)
        }
        updateFuzzyDictionarySuggestions(for: sessions[index])
        statusMessage = "Transcript updated."
        scheduleSave()
    }

    func addReplacementRule(find: String, replace: String) {
        let find = find.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !find.isEmpty else { return }
        replacementRules.append(ReplacementRule(find: find, replace: replace))
        statusMessage = "Replacement rule added."
    }

    func removeReplacementRules(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            replacementRules.remove(at: offset)
        }
    }

    func addCustomDictionaryTerm(_ value: String) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard let profileIndex = selectedCustomDictionaryProfileIndex else { return }
        guard customDictionaryProfiles[profileIndex].terms.contains(where: { $0.value.caseInsensitiveCompare(value) == .orderedSame }) == false else { return }
        customDictionaryProfiles[profileIndex].terms.append(CustomDictionaryTerm(value: value))
        refreshSelectedSessionFuzzyDictionarySuggestions()
        statusMessage = "Dictionary term added."
    }

    func removeCustomDictionaryTerms(at offsets: IndexSet) {
        guard let profileIndex = selectedCustomDictionaryProfileIndex else { return }
        for offset in offsets.sorted(by: >) {
            customDictionaryProfiles[profileIndex].terms.remove(at: offset)
        }
        refreshSelectedSessionFuzzyDictionarySuggestions()
    }

    func addCustomDictionaryProfile(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let profile = CustomDictionaryProfile(name: name)
        customDictionaryProfiles.append(profile)
        selectedCustomDictionaryProfileID = profile.id
        statusMessage = "Dictionary profile added."
    }

    func removeCustomDictionaryProfiles(at offsets: IndexSet) {
        let sortedOffsets = offsets.sorted(by: >)
        for offset in sortedOffsets where customDictionaryProfiles.indices.contains(offset) {
            guard customDictionaryProfiles.count > 1 else { return }
            customDictionaryProfiles.remove(at: offset)
        }
        if !customDictionaryProfiles.contains(where: { $0.id == selectedCustomDictionaryProfileID }),
           let firstProfileID = customDictionaryProfiles.first?.id {
            selectedCustomDictionaryProfileID = firstProfileID
        }
        refreshSelectedSessionFuzzyDictionarySuggestions()
    }

    func setSelectedCustomDictionaryProfileFuzzyMatchingEnabled(_ isEnabled: Bool) {
        guard let profileIndex = selectedCustomDictionaryProfileIndex else { return }
        customDictionaryProfiles[profileIndex].fuzzyMatchingEnabled = isEnabled
        refreshSelectedSessionFuzzyDictionarySuggestions()
        statusMessage = isEnabled ? "Fuzzy dictionary review enabled for this profile." : "Fuzzy dictionary review disabled for this profile."
    }

    func promoteLastManualEditReplacement() {
        guard var suggestion = lastManualReplacementSuggestion else { return }
        suggestion.isEnabled = true
        replacementRules.append(suggestion)
        lastManualReplacementSuggestion = nil
        statusMessage = "Manual edit saved as a replacement rule."
    }

    private func applyReplacementRules(to text: String) -> String {
        let replaced = ReplacementRuleEngine(rules: replacementRules).apply(to: text)
        return CustomDictionaryEngine(terms: selectedCustomDictionaryTerms).apply(to: replaced)
    }

    func fuzzyDictionarySuggestions(for sessionID: TranscriptSession.ID) -> [FuzzyDictionarySuggestion] {
        fuzzyDictionarySuggestions.filter { $0.sessionID == sessionID }
    }

    func applyFuzzyDictionarySuggestion(_ suggestion: FuzzyDictionarySuggestion) {
        guard let index = sessions.firstIndex(where: { $0.id == suggestion.sessionID }) else { return }

        let engine = CustomDictionaryEngine(terms: selectedCustomDictionaryTerms)
        let updated = engine.apply(suggestion, to: sessions[index].displayTranscript)
        guard updated != sessions[index].displayTranscript else {
            dismissFuzzyDictionarySuggestion(suggestion)
            return
        }

        if !sessions[index].finalTranscript.isEmpty {
            sessions[index].finalTranscript = updated
        } else if !sessions[index].liveTranscript.isEmpty {
            sessions[index].liveTranscript = updated
        }
        sessions[index].transcript = updated
        fuzzyDictionarySuggestions.removeAll { $0.id == suggestion.id }
        updateFuzzyDictionarySuggestions(for: sessions[index])
        statusMessage = "Applied fuzzy dictionary suggestion."
        scheduleSave()
    }

    func dismissFuzzyDictionarySuggestion(_ suggestion: FuzzyDictionarySuggestion) {
        fuzzyDictionarySuggestions.removeAll { $0.id == suggestion.id }
        statusMessage = "Dismissed fuzzy dictionary suggestion."
    }

    private func refreshSelectedSessionFuzzyDictionarySuggestions() {
        guard let session = selectedSession else { return }
        updateFuzzyDictionarySuggestions(for: session)
    }

    private func updateFuzzyDictionarySuggestions(for session: TranscriptSession) {
        fuzzyDictionarySuggestions.removeAll { $0.sessionID == session.id }
        guard let profile = selectedCustomDictionaryProfile, profile.fuzzyMatchingEnabled else { return }

        let candidates = CustomDictionaryEngine(terms: profile.terms).fuzzySuggestions(in: session.displayTranscript)
        fuzzyDictionarySuggestions.append(
            contentsOf: candidates.map {
                FuzzyDictionarySuggestion(
                    sessionID: session.id,
                    profileID: profile.id,
                    original: $0.original,
                    replacement: $0.replacement,
                    occurrenceCount: $0.occurrenceCount,
                    similarity: $0.similarity
                )
            }
        )
    }

    private func finalPassVocabularyBoostingRequest() -> VocabularyBoostingRequest? {
        guard finalPassVocabularyBoostingEnabled else { return nil }
        let enabledTerms = selectedCustomDictionaryTerms
            .filter(\.isEnabled)
            .map(\.value)
        return VocabularyBoostingRequest(
            terms: enabledTerms,
            allowsModelDownload: !offlineMode
        )
    }

    var selectedCustomDictionaryProfile: CustomDictionaryProfile? {
        customDictionaryProfiles.first { $0.id == selectedCustomDictionaryProfileID }
    }

    var selectedCustomDictionaryTerms: [CustomDictionaryTerm] {
        selectedCustomDictionaryProfile?.terms ?? []
    }

    private var selectedCustomDictionaryProfileIndex: Int? {
        customDictionaryProfiles.firstIndex { $0.id == selectedCustomDictionaryProfileID }
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

    func batchExportVisibleTranscripts(format: TranscriptExportFormat) {
        let exportableSessions = filteredSessions.filter { !$0.displayTranscript.isEmpty }
        guard !exportableSessions.isEmpty else {
            statusMessage = "No visible transcripts to export."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose a folder for exported transcripts."

        guard panel.runModal() == .OK, let outputDirectory = panel.url else { return }

        let urls = BatchExportPlanner.destinationURLs(
            for: exportableSessions,
            format: format,
            outputDirectory: outputDirectory
        )
        var failures: [String] = []

        for session in exportableSessions {
            guard let url = urls[session.id] else { continue }
            do {
                try exportData(for: session, format: format).write(to: url, options: [.atomic])
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if failures.isEmpty {
            statusMessage = "Exported \(exportableSessions.count) transcript\(exportableSessions.count == 1 ? "" : "s")."
        } else {
            statusMessage = "Exported \(exportableSessions.count - failures.count); \(failures.count) failed. \(failures.prefix(2).joined(separator: " "))"
        }
    }

    func deleteSession(sessionID: TranscriptSession.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let session = sessions.remove(at: index)
        deleteFiles(for: session)
        liveChunkStats[sessionID] = nil
        failedLiveChunks[sessionID] = nil
        fuzzyDictionarySuggestions.removeAll { $0.sessionID == sessionID }

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

    private func finalizeDictationStorage(sessionID: TranscriptSession.ID) {
        guard dictationSessionID == sessionID else { return }
        dictationSessionID = nil

        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let mode = dictationStorageMode

        if mode.deletesAudio {
            deleteAudioFile(for: sessions[index])
            deleteChunkFiles(for: sessions[index])
            sessions[index].duration = nil
            sessions[index].fileSize = nil
            sessions[index].isAudioEncrypted = false
        }

        if mode.keepsTranscript {
            statusMessage = mode.deletesAudio ? "Dictation transcript saved; temporary audio deleted." : statusMessage
            scheduleSave()
        } else {
            let deletedSession = sessions.remove(at: index)
            liveChunkStats[deletedSession.id] = nil
            failedLiveChunks[deletedSession.id] = nil
            if selectedSessionID == deletedSession.id {
                selectedSessionID = sessions.first?.id
            }
            statusMessage = "Dictation pasted and removed from history."
            scheduleSave()
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

    private func copyImportedAudio(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: recordingsDirectoryURL, withIntermediateDirectories: true)
        let extensionName = sourceURL.pathExtension.lowercased()
        let destinationURL = recordingsDirectoryURL.appending(path: "import-\(UUID().uuidString).\(extensionName)")
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
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
        "\(BatchExportPlanner.exportBaseName(for: session)).\(format.fileExtension)"
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
    case downloadRequired(String)
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
        case let .downloadRequired(model):
            "\(model) required"
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
        case .downloadRequired:
            "Offline mode blocks model downloads. Turn it off once to cache the selected model."
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
