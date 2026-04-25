import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: TranscriptionStore

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
                Toggle("Paste after Command-Shift-D dictation", isOn: $store.autoPasteDictation)

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
            }

            Section("Hotkey") {
                Picker("Dictation paste", selection: $store.dictationHotKey) {
                    ForEach(DictationHotKey.allCases) { hotKey in
                        Text(hotKey.label).tag(hotKey)
                    }
                }

                Text("Changing this shortcut re-registers the global dictation hotkey immediately.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560)
    }
}
