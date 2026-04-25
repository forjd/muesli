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
            }

            HStack(spacing: 10) {
                Image(systemName: "cpu")
                    .foregroundStyle(.secondary)
                Text(store.selectedModel.label)
                Text(store.selectedModel.detail)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.callout)
        }
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
                    }

                    Spacer()

                    Button("Copy", systemImage: "doc.on.doc") {
                        store.copyTranscript(sessionID: session.id)
                    }
                    .disabled(session.transcript.isEmpty)

                    Menu {
                        Button("Text") {
                            store.exportTranscript(sessionID: session.id, format: .text)
                        }

                        Button("JSON") {
                            store.exportTranscript(sessionID: session.id, format: .json)
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(session.transcript.isEmpty)

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

                Text(session.transcript.isEmpty ? "Transcript will appear here after the Parakeet sidecar finishes." : session.transcript)
                    .font(.body)
                    .lineSpacing(4)
                    .foregroundStyle(session.transcript.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding()
        }
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
