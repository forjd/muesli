import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: TranscriptionStore
    @StateObject private var hotKeyRecorder = HotKeyRecorder()
    @State private var isShowingDeleteAllConfirmation = false
    @State private var replacementFind = ""
    @State private var replacementReplace = ""
    @State private var dictionaryTerm = ""
    @State private var dictionaryProfileName = ""

    var body: some View {
        Form {
            Section("Model") {
                Picker("Default model", selection: $store.selectedModel) {
                    ForEach(ParakeetModel.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }

                LabeledContent("Backend") {
                    Text("FluidAudio")
                        .foregroundStyle(.secondary)
                }

                Text(store.selectedModel.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Dictation") {
                Toggle("Paste after hotkey dictation", isOn: $store.autoPasteDictation)

                Picker("Save after dictation", selection: $store.dictationStorageMode) {
                    ForEach(DictationStorageMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Text(store.dictationStorageMode.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("Sound effects", isOn: $store.soundEffectsEnabled)

                Text("Play short system sounds for recording start, stop, cancellation, failure, and paste feedback.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker("Recording overlay", selection: $store.recordingOverlayAnchor) {
                    ForEach(RecordingOverlayAnchor.allCases) { anchor in
                        Text(anchor.label).tag(anchor)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Clipboard fallback") {
                    Text("Always copy before paste")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Paste delay")
                        Spacer()
                        Text(store.pasteDelay.formatted(.number.precision(.fractionLength(2))) + "s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: $store.pasteDelay, in: 0.1...2.0, step: 0.05)
                }

                Text("Increase the delay if the previous app needs longer to become active before paste is sent.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Toggle("Offline mode", isOn: $store.offlineMode)

                Text("Offline mode blocks model downloads and future remote features. If the selected model is not cached, Muesli will ask you to turn offline mode off before recording or transcribing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LabeledContent("Current mode") {
                    Label(store.offlineMode ? "Offline local dictation" : store.privacyMode.label, systemImage: store.offlineMode ? "wifi.slash" : (store.privacyMode.contentLeavesDevice ? "network" : "lock.shield"))
                        .foregroundStyle(store.privacyMode.contentLeavesDevice ? .orange : .secondary)
                }

                LabeledContent("Content leaves this Mac") {
                    Text(store.privacyMode.contentLeavesDevice ? "Yes" : "No")
                        .foregroundStyle(store.privacyMode.contentLeavesDevice ? .orange : .secondary)
                }

                LabeledContent("Network use") {
                    Text(store.offlineMode ? "Disabled after cached models" : store.privacyMode.networkUse)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Local storage encryption") {
                    Text("On; key stored in Keychain")
                        .foregroundStyle(.secondary)
                }

                Text(store.privacyMode.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                LabeledContent("Recordings folder") {
                    HStack {
                        Text(store.recordingsDirectoryURL.path)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Button("Open", systemImage: "folder") {
                            store.openRecordingsFolder()
                        }
                    }
                }

                Toggle("Delete raw audio after transcription", isOn: $store.deleteAudioAfterTranscription)

                Text("Deleting raw audio keeps saved transcripts but removes the original recording file after successful transcription.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker("Auto-delete", selection: $store.retentionPolicy.target) {
                    ForEach(RetentionTarget.allCases) { target in
                        Text(target.label).tag(target)
                    }
                }

                Stepper(
                    value: $store.retentionPolicy.days,
                    in: 1...365,
                    step: 1
                ) {
                    LabeledContent("After") {
                        Text("\(store.retentionPolicy.days) day\(store.retentionPolicy.days == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .disabled(!store.retentionPolicy.isEnabled)

                Text(store.retentionPolicy.target.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()

                Button("Delete All Recordings and Transcripts", systemImage: "trash", role: .destructive) {
                    isShowingDeleteAllConfirmation = true
                }
                .disabled(store.sessions.isEmpty && !store.isRecording)
            }

            Section("Hotkey") {
                LabeledContent("Dictation paste") {
                    HStack(spacing: 8) {
                        Text(hotKeyRecorder.isRecording ? "Press a shortcut..." : store.dictationHotKey.label)
                            .foregroundStyle(hotKeyRecorder.isRecording ? .blue : .secondary)
                            .monospacedDigit()

                        Menu("Presets") {
                            ForEach(DictationHotKey.presets) { hotKey in
                                Button(hotKey.label) {
                                    store.dictationHotKey = hotKey
                                }
                            }
                        }

                        Button(hotKeyRecorder.isRecording ? "Cancel" : "Record", systemImage: hotKeyRecorder.isRecording ? "xmark.circle" : "keyboard") {
                            if hotKeyRecorder.isRecording {
                                hotKeyRecorder.stop()
                            } else {
                                hotKeyRecorder.start { hotKey in
                                    store.dictationHotKey = hotKey
                                }
                            }
                        }
                    }
                }

                if let errorMessage = hotKeyRecorder.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                Picker("Behavior", selection: $store.dictationHotKeyMode) {
                    ForEach(DictationHotKeyMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Text(store.dictationHotKeyMode.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Custom shortcuts must include Command, Option, or Control. Press Escape to cancel recording.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Replacements") {
                HStack {
                    TextField("Find", text: $replacementFind)
                    TextField("Replace with", text: $replacementReplace)
                    Button("Add", systemImage: "plus") {
                        store.addReplacementRule(find: replacementFind, replace: replacementReplace)
                        replacementFind = ""
                        replacementReplace = ""
                    }
                    .disabled(replacementFind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let suggestion = store.lastManualReplacementSuggestion {
                    Button("Promote Last Manual Edit", systemImage: "wand.and.stars") {
                        store.promoteLastManualEditReplacement()
                    }
                    Text("Suggested replacement: \(suggestion.find) -> \(suggestion.replace)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if store.replacementRules.isEmpty {
                    Text("Replacement rules run after transcription for deterministic cleanup.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(store.replacementRules) { rule in
                            HStack {
                                Text(rule.find)
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.secondary)
                                Text(rule.replace)
                                Spacer()
                                if !rule.isEnabled {
                                    Text("Off")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: store.removeReplacementRules)
                    }
                    .frame(minHeight: 90)
                }
            }

            Section("Custom Dictionary") {
                Picker("Profile", selection: $store.selectedCustomDictionaryProfileID) {
                    ForEach(store.customDictionaryProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }

                HStack {
                    TextField("New profile", text: $dictionaryProfileName)
                    Button("Add Profile", systemImage: "person.crop.circle.badge.plus") {
                        store.addCustomDictionaryProfile(name: dictionaryProfileName)
                        dictionaryProfileName = ""
                    }
                    .disabled(dictionaryProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack {
                    TextField("Preferred word, name, acronym, or term", text: $dictionaryTerm)
                    Button("Add", systemImage: "plus") {
                        store.addCustomDictionaryTerm(dictionaryTerm)
                        dictionaryTerm = ""
                    }
                    .disabled(dictionaryTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if store.selectedCustomDictionaryTerms.isEmpty {
                    Text("Terms in the selected profile are applied as a correction layer after transcription.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(store.selectedCustomDictionaryTerms) { term in
                            HStack {
                                Text(term.value)
                                Spacer()
                                if !term.isEnabled {
                                    Text("Off")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: store.removeCustomDictionaryTerms)
                    }
                    .frame(minHeight: 90)
                }

                if store.customDictionaryProfiles.count > 1 {
                    List {
                        ForEach(store.customDictionaryProfiles) { profile in
                            HStack {
                                Text(profile.name)
                                Spacer()
                                Text("\(profile.terms.count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .onDelete(perform: store.removeCustomDictionaryProfiles)
                    }
                    .frame(minHeight: 90)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 620)
        .onDisappear {
            hotKeyRecorder.stop()
        }
        .confirmationDialog(
            "Delete all recordings and transcripts?",
            isPresented: $isShowingDeleteAllConfirmation
        ) {
            Button("Delete All", role: .destructive) {
                store.deleteAllSessions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved recording, transcript, and live chunk from Muesli. This cannot be undone.")
        }
    }
}

@MainActor
private final class HotKeyRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var errorMessage: String?

    private var monitor: Any?

    func start(onRecord: @escaping (DictationHotKey) -> Void) {
        stop()
        isRecording = true
        errorMessage = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.stop()
                return nil
            }

            guard let hotKey = DictationHotKey(event: event) else {
                self.errorMessage = "Use Command, Option, or Control with a letter, number, or Space."
                return nil
            }

            onRecord(hotKey)
            self.stop()
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
