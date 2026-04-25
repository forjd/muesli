import SwiftUI

struct DetailView: View {
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        VStack(spacing: 0) {
            RecorderHeaderView(store: store)
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .background(.bar)

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Muesli")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                    Text(store.statusMessage)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                AudioLevelMeter(level: store.currentAudioLevel)
                    .frame(width: 220)

                if store.isWarmingModel {
                    ProgressView()
                        .controlSize(.small)
                }

                TranscriberHealthMenu(store: store)
            }

            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .foregroundStyle(.secondary)
                Text(store.selectedModel.label)
                    .fontWeight(.medium)
                Text(store.selectedModel.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

                if !session.benchmarks.isEmpty {
                    BenchmarkView(benchmarks: session.benchmarks)
                }
            }

            TranscriptTextView(session: session)
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

            Button("Benchmark", systemImage: "speedometer") {
                Task { await store.benchmark(sessionID: session.id) }
            }
            .disabled(store.isBusy || store.isRecording)

            Button("Transcribe", systemImage: "text.bubble") {
                Task { await store.transcribe(sessionID: session.id) }
            }
            .disabled(session.status == .transcribing || store.isBusy || store.isRecording)

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
            Button("Benchmark", systemImage: "speedometer") {
                Task { await store.benchmark(sessionID: session.id) }
            }
            .disabled(store.isBusy || store.isRecording)

            Button("Transcribe", systemImage: "text.bubble") {
                Task { await store.transcribe(sessionID: session.id) }
            }
            .disabled(session.status == .transcribing || store.isBusy || store.isRecording)

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

private struct BenchmarkView: View {
    let benchmarks: [TranscriptionBenchmark]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Benchmarks")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(benchmarks) { benchmark in
                    GridRow {
                        Text(benchmark.model.label)
                        Text("\(benchmark.duration.formatted(.number.precision(.fractionLength(2))))s")
                            .monospacedDigit()
                        Text("\(benchmark.transcriptLength) chars")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.callout)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
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
                    text: session.displayTranscript.isEmpty ? "Transcript will appear here after FluidAudio finishes." : session.displayTranscript,
                    isPlaceholder: session.displayTranscript.isEmpty
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TranscriptBlock: View {
    let title: String
    let text: String
    let isPlaceholder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()
            }

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
