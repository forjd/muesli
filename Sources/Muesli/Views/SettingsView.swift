import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: TranscriptionStore
    @StateObject private var hotKeyRecorder = HotKeyRecorder()
    @State private var isShowingDeleteAllConfirmation = false

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
                LabeledContent("Current mode") {
                    Label(store.privacyMode.label, systemImage: store.privacyMode.contentLeavesDevice ? "network" : "lock.shield")
                        .foregroundStyle(store.privacyMode.contentLeavesDevice ? .orange : .secondary)
                }

                LabeledContent("Content leaves this Mac") {
                    Text(store.privacyMode.contentLeavesDevice ? "Yes" : "No")
                        .foregroundStyle(store.privacyMode.contentLeavesDevice ? .orange : .secondary)
                }

                LabeledContent("Network use") {
                    Text(store.privacyMode.networkUse)
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
