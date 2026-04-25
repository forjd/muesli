import SwiftUI

struct DetailView: View {
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        VStack(spacing: 0) {
            RecorderHeaderView(store: store)
                .padding()
                .background(.regularMaterial)

            Divider()

            if let session = store.selectedSession {
                TranscriptDetail(session: session, store: store)
            } else {
                ContentUnavailableView("Start Recording", systemImage: "mic", description: Text("Record a clip to create a transcription session."))
            }
        }
    }
}

private struct RecorderHeaderView: View {
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Muesli")
                        .font(.title2.weight(.semibold))
                    Text(store.statusMessage)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                AudioLevelMeter(level: store.currentAudioLevel)
                    .frame(width: 180)

                Button {
                    Task { await store.toggleRecording() }
                } label: {
                    Label(store.isRecording ? "Stop" : "Record", systemImage: store.isRecording ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await store.transcribeLatestRecording() }
                } label: {
                    Label("Transcribe", systemImage: "text.bubble.fill")
                }
                .disabled(store.latestRecordingURL == nil || store.isBusy)

                if store.isWarmingModel {
                    ProgressView()
                        .controlSize(.small)
                }

                WorkerHealthMenu(store: store)
            }

            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .foregroundStyle(.secondary)
                Text(store.selectedModel.label)
                Text(store.selectedModel.detail)
                    .foregroundStyle(.secondary)
                Spacer()

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

private struct WorkerHealthMenu: View {
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        Menu {
            if let health = store.workerHealth {
                Label(health.isRunning ? "Running" : "Stopped", systemImage: health.isRunning ? "checkmark.circle" : "xmark.circle")

                if let processID = health.processID {
                    Text("PID \(processID)")
                }

                Text(health.logURL.path)
                    .textSelection(.enabled)
            } else {
                Text("Worker not checked")
            }

            Divider()

            Button("Refresh", systemImage: "arrow.clockwise") {
                store.refreshWorkerHealth()
            }

            Button("Restart", systemImage: "power") {
                Task { await store.restartWorker() }
            }
        } label: {
            Label("Worker", systemImage: "server.rack")
        }
        .disabled(store.isBusy || store.isRecording)
    }
}

private struct TranscriptDetail: View {
    let session: TranscriptSession
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.createdAt, format: .dateTime.weekday().month().day().hour().minute())
                            .font(.title3.weight(.semibold))
                        Text(session.audioURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)

                        if let stats = store.liveChunkStats[session.id], stats.submitted > 0 {
                            LiveChunkStatsView(stats: stats)
                        }
                    }

                    Spacer()

                    if let stats = store.liveChunkStats[session.id], stats.failed > 0 {
                        Button("Retry", systemImage: "arrow.clockwise") {
                            store.retryFailedChunks(sessionID: session.id)
                        }
                    }

                    Button("Delete", systemImage: "trash", role: .destructive) {
                        store.deleteSession(sessionID: session.id)
                    }

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

                    Button("Transcribe", systemImage: "text.bubble") {
                        Task { await store.transcribe(sessionID: session.id) }
                    }
                    .disabled(session.status == .transcribing || store.isBusy || store.isRecording)
                }

                if session.status == .failed, let errorMessage = session.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }

                TranscriptTextView(session: session)
            }
            .padding()
        }
    }
}

private struct TranscriptTextView: View {
    let session: TranscriptSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !session.finalTranscript.isEmpty && !session.liveTranscript.isEmpty && session.finalTranscript != session.liveTranscript {
                TranscriptBlock(title: "Final", text: session.finalTranscript, isPlaceholder: false)
                TranscriptBlock(title: "Live", text: session.liveTranscript, isPlaceholder: false)
            } else {
                TranscriptBlock(
                    title: session.finalTranscript.isEmpty ? "Transcript" : "Final",
                    text: session.displayTranscript.isEmpty ? "Transcript will appear here after the Parakeet sidecar finishes." : session.displayTranscript,
                    isPlaceholder: session.displayTranscript.isEmpty
                )
            }
        }
    }
}

private struct TranscriptBlock: View {
    let title: String
    let text: String
    let isPlaceholder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.body)
                .lineSpacing(4)
                .foregroundStyle(isPlaceholder ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
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
                    .fill(.green)
                    .frame(width: proxy.size.width * normalized)
            }
        }
        .frame(height: 8)
        .accessibilityLabel("Audio level")
    }
}
