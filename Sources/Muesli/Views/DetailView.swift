import SwiftUI

struct DetailView: View {
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        VStack(spacing: 0) {
            RecorderHeaderView(store: store)
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
                .background(.bar)

            Divider()

            if let session = store.selectedSession {
                TranscriptDetail(session: session, store: store)
            } else {
                EmptyRecordingView(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct RecorderHeaderView: View {
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Muesli")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                    Text(store.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                PrivacyModeBadge(mode: store.privacyMode, isOffline: store.offlineMode)

                ModelLoadBadge(state: store.modelLoadState)

                TranscriberHealthMenu(store: store)
            }

            HStack(alignment: .center, spacing: 14) {
                Label {
                    HStack(spacing: 8) {
                        Text(store.selectedModel.label)
                            .fontWeight(.semibold)
                        Text(store.selectedModel.detail)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } icon: {
                    Image(systemName: "cpu")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                AudioLevelMeter(level: store.currentAudioLevel)
                    .frame(width: 240)

                if store.isRecording {
                    Label(formatElapsed(store.recordingElapsed), systemImage: "timer")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
    }

    private func formatElapsed(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed.rounded(.down)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct PrivacyModeBadge: View {
    let mode: PrivacyMode
    let isOffline: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isOffline ? "wifi.slash" : (mode.contentLeavesDevice ? "network" : "lock.shield.fill"))
                .foregroundStyle(mode.contentLeavesDevice ? .orange : .green)

            Text(isOffline ? "Offline" : mode.shortLabel)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .help(isOffline ? "Network access is blocked after required models are cached." : mode.detail)
    }
}

private struct ModelLoadBadge: View {
    let state: ModelLoadState

    var body: some View {
        HStack(spacing: 8) {
            if state.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: iconName)
                    .foregroundStyle(color)
            }

            Text(state.label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .help(state.detail)
    }

    private var iconName: String {
        switch state {
        case .idle:
            "circle"
        case .loadingCached:
            "externaldrive.fill"
        case .downloading:
            "arrow.down.circle"
        case .downloadRequired:
            "icloud.slash"
        case .ready:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .idle:
            .secondary
        case .loadingCached:
            .blue
        case .downloading:
            .blue
        case .downloadRequired:
            .orange
        case .ready:
            .green
        case .failed:
            .orange
        }
    }
}

private struct EmptyRecordingView: View {
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: store.isRecording ? "waveform.circle.fill" : "mic.circle")
                .font(.system(size: 64, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(store.isRecording ? .red : .secondary)

            VStack(spacing: 6) {
                Text(store.isRecording ? "Recording" : "Start Recording")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))

                Text(store.isRecording ? "Speak naturally. Stop recording to create a transcript." : "Record a clip to create a transcription session.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await store.toggleRecording() }
                } label: {
                    Label(store.isRecording ? "Stop Recording" : "Record", systemImage: store.isRecording ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    Task { await store.toggleDictationPaste() }
                } label: {
                    Label("Dictate", systemImage: "keyboard")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(store.isBusy)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TranscriberHealthMenu: View {
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        Menu {
            if let health = store.transcriberHealth {
                Label(health.isRunning ? "Running" : "Stopped", systemImage: health.isRunning ? "checkmark.circle" : "xmark.circle")

                if let modelVersion = health.modelVersion {
                    Text("Model \(modelVersion)")
                }
            } else {
                Text("Transcriber not checked")
            }

            Divider()

            Button("Refresh", systemImage: "arrow.clockwise") {
                store.refreshTranscriberHealth()
            }

            Button("Reset", systemImage: "power") {
                Task { await store.resetTranscriber() }
            }
        } label: {
            Label("Engine", systemImage: "waveform")
        }
        .disabled(store.isBusy || store.isRecording)
    }
}

private struct TranscriptDetail: View {
    let session: TranscriptSession
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                RecordingSummary(session: session, stats: store.liveChunkStats[session.id])

                RecordingActionBar(session: session, store: store)

                if session.status == .failed, let errorMessage = session.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

            }

                TranscriptTextView(session: session, store: store)
                    .layoutPriority(1)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: 980, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct RecordingSummary: View {
    let session: TranscriptSession
    let stats: LiveChunkStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(session.createdAt, format: .dateTime.weekday().month().day().hour().minute())
                    .font(.system(.title2, design: .rounded, weight: .semibold))

                StatusBadge(status: session.status)

                Spacer()
            }

            HStack(spacing: 12) {
                Label(shortPath(session.audioURL), systemImage: "waveform.path.ecg")
                    .lineLimit(1)
                    .help(session.audioURL.path)
                    .textSelection(.enabled)

                if let duration = session.duration {
                    Divider()
                        .frame(height: 14)
                    Label(formatDuration(duration), systemImage: "timer")
                }

                if let fileSize = session.fileSize {
                    Divider()
                        .frame(height: 14)
                    Text(formatBytes(fileSize))
                }

                if let stats, stats.submitted > 0 {
                    Divider()
                        .frame(height: 14)
                    LiveChunkStatsView(stats: stats)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func shortPath(_ url: URL) -> String {
        let parent = url.deletingLastPathComponent().lastPathComponent
        return "\(parent)/\(url.lastPathComponent)"
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct RecordingActionBar: View {
    let session: TranscriptSession
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullLayout
            compactLayout
        }
        .buttonStyle(.bordered)
    }

    private var fullLayout: some View {
        HStack(spacing: 10) {
            if let stats = store.liveChunkStats[session.id], stats.failed > 0 {
                Button("Retry", systemImage: "arrow.clockwise") {
                    store.retryFailedChunks(sessionID: session.id)
                }
            }

            Button("Transcribe", systemImage: "text.bubble") {
                Task { await store.transcribe(sessionID: session.id) }
            }
            .disabled(session.status == .transcribing || store.isBusy || store.isRecording)

            if store.isRecording, session.status == .recording {
                Button("Cancel", systemImage: "xmark.circle", role: .destructive) {
                    store.cancelDictation()
                }
            }

            Spacer()

            Button("Copy", systemImage: "doc.on.doc") {
                store.copyTranscript(sessionID: session.id)
            }
            .disabled(session.displayTranscript.isEmpty)

            Menu {
                Button("Text") {
                    store.exportTranscript(sessionID: session.id, format: .text)
                }

                Button("JSON") {
                    store.exportTranscript(sessionID: session.id, format: .json)
                }

                Button("SRT") {
                    store.exportTranscript(sessionID: session.id, format: .srt)
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(session.displayTranscript.isEmpty)

            Button("Delete", systemImage: "trash", role: .destructive) {
                store.deleteSession(sessionID: session.id)
            }
        }
    }

    private var compactLayout: some View {
        HStack(spacing: 10) {
            Button("Transcribe", systemImage: "text.bubble") {
                Task { await store.transcribe(sessionID: session.id) }
            }
            .disabled(session.status == .transcribing || store.isBusy || store.isRecording)

            if store.isRecording, session.status == .recording {
                Button("Cancel", systemImage: "xmark.circle", role: .destructive) {
                    store.cancelDictation()
                }
            }

            Spacer()

            Menu {
                Button("Copy", systemImage: "doc.on.doc") {
                    store.copyTranscript(sessionID: session.id)
                }
                .disabled(session.displayTranscript.isEmpty)

                Button("Export Text") {
                    store.exportTranscript(sessionID: session.id, format: .text)
                }
                .disabled(session.displayTranscript.isEmpty)

                Button("Export JSON") {
                    store.exportTranscript(sessionID: session.id, format: .json)
                }
                .disabled(session.displayTranscript.isEmpty)

                Button("Export SRT") {
                    store.exportTranscript(sessionID: session.id, format: .srt)
                }
                .disabled(session.displayTranscript.isEmpty)

                Divider()

                Button("Delete", systemImage: "trash", role: .destructive) {
                    store.deleteSession(sessionID: session.id)
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }
}

private struct StatusBadge: View {
    let status: TranscriptStatus

    var body: some View {
        Label(status.rawValue, systemImage: iconName)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var iconName: String {
        switch status {
        case .recording:
            "mic.fill"
        case .recorded:
            "waveform"
        case .finalizing:
            "hourglass"
        case .transcribing:
            "arrow.triangle.2.circlepath"
        case .complete:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .recording:
            .red
        case .recorded, .finalizing, .transcribing:
            .blue
        case .complete:
            .green
        case .failed:
            .orange
        }
    }
}

private struct TranscriptTextView: View {
    let session: TranscriptSession
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !session.finalTranscript.isEmpty && !session.liveTranscript.isEmpty && session.finalTranscript != session.liveTranscript {
                TranscriptBlock(
                    sessionID: session.id,
                    title: "Final",
                    text: session.finalTranscript,
                    isPlaceholder: false,
                    store: store
                )
                TranscriptBlock(
                    sessionID: session.id,
                    title: "Live",
                    text: session.liveTranscript,
                    isPlaceholder: false,
                    store: store
                )
            } else {
                TranscriptBlock(
                    sessionID: session.id,
                    title: session.finalTranscript.isEmpty ? "Transcript" : "Final",
                    text: session.displayTranscript.isEmpty ? "Transcript will appear here after FluidAudio finishes." : session.displayTranscript,
                    isPlaceholder: session.displayTranscript.isEmpty,
                    store: store
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TranscriptBlock: View {
    let sessionID: TranscriptSession.ID
    let title: String
    let text: String
    let isPlaceholder: Bool
    @ObservedObject var store: TranscriptionStore
    @State private var isEditing = false
    @State private var draftText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if !isPlaceholder {
                    Button(isEditing ? "Done" : "Edit", systemImage: isEditing ? "checkmark" : "pencil") {
                        if isEditing {
                            store.updateTranscript(sessionID: sessionID, text: draftText)
                        } else {
                            draftText = text
                        }
                        isEditing.toggle()
                    }
                    .buttonStyle(.borderless)
                }
            }

            if isEditing {
                TextEditor(text: $draftText)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(7)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .serif))
                        .lineSpacing(7)
                        .foregroundStyle(isPlaceholder ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.trailing, 8)
                }
                .scrollIndicators(.automatic)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            draftText = text
        }
        .onChange(of: text) { _, newValue in
            if !isEditing {
                draftText = newValue
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct LiveChunkStatsView: View {
    let stats: LiveChunkStats

    var body: some View {
        HStack(spacing: 8) {
            Label("\(stats.completed)/\(stats.submitted)", systemImage: "waveform.badge.mic")

            if stats.failed > 0 {
                Label("\(stats.failed)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct AudioLevelMeter: View {
    let level: Float

    private var normalized: Double {
        let clamped = min(max(level, -60), 0)
        return Double((clamped + 60) / 60)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(level > -45 ? .green : .secondary)
                    .frame(width: proxy.size.width * normalized)
            }
        }
        .frame(height: 7)
        .accessibilityLabel("Audio level")
    }
}
