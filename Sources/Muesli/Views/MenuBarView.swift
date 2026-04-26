import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: TranscriptionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusHeader

            Divider()

            Button {
                Task { await store.toggleDictationPaste() }
            } label: {
                Label(dictationTitle, systemImage: store.isRecording ? "stop.circle.fill" : "mic.badge.plus")
            }
            .disabled(store.isBusy && !store.isRecording)

            if store.isRecording {
                Button(role: .destructive) {
                    store.cancelDictation()
                } label: {
                    Label("Cancel Recording", systemImage: "xmark.circle")
                }
            }

            Button {
                Task { await store.toggleRecording() }
            } label: {
                Label(store.isRecording ? "Stop Recording" : "Start Recording", systemImage: store.isRecording ? "stop.fill" : "record.circle")
            }
            .disabled(store.isBusy && !store.isRecording)

            Button {
                Task { await store.transcribeLatestRecording() }
            } label: {
                Label("Transcribe Latest", systemImage: "text.bubble")
            }
            .disabled(store.latestRecordingURL == nil || store.isBusy)

            Divider()

            Picker("Model", selection: $store.selectedModel) {
                ForEach(ParakeetModel.allCases) { model in
                    Text(model.label).tag(model)
                }
            }
            .disabled(store.isBusy || store.isRecording || store.isWarmingModel)

            Toggle("Paste After Dictation", isOn: $store.autoPasteDictation)

            Divider()

            Button {
                openMainWindow()
            } label: {
                Label("Open Muesli", systemImage: "macwindow")
            }

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }

            Button {
                store.openRecordingsFolder()
            } label: {
                Label("Recordings Folder", systemImage: "folder")
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Muesli", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(statusTitle, systemImage: statusSymbolName)
                .font(.headline)
                .foregroundStyle(statusColor)

            Text(statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Label(store.offlineMode ? "Offline local dictation" : store.privacyMode.label, systemImage: store.offlineMode ? "wifi.slash" : (store.privacyMode.contentLeavesDevice ? "network" : "lock.shield"))
                .font(.caption)
                .foregroundStyle(store.privacyMode.contentLeavesDevice ? .orange : .secondary)
                .help(store.privacyMode.detail)

            if store.isRecording {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(formatElapsed(store.recordingElapsed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var dictationTitle: String {
        store.isRecording ? "Stop and Paste" : "Dictate and Paste"
    }

    private var statusTitle: String {
        if store.isRecording {
            return "Recording"
        }
        if store.isBusy {
            return "Transcribing"
        }
        return "Muesli"
    }

    private var statusDetail: String {
        if store.statusMessage.isEmpty {
            return store.modelLoadState.label
        }
        return store.statusMessage
    }

    private var statusSymbolName: String {
        if store.isRecording {
            return "mic.circle.fill"
        }
        if store.isBusy {
            return "waveform"
        }
        if store.modelLoadState.isReady {
            return "checkmark.circle.fill"
        }
        return "mic.circle"
    }

    private var statusColor: Color {
        if store.isRecording {
            return .red
        }
        if store.modelLoadState.isReady {
            return .green
        }
        return .primary
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func formatElapsed(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
