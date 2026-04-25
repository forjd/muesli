import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TranscriptionStore
    @SceneStorage("selectedSessionID") private var selectedSessionIDString: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            DetailView(store: store)
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Model", selection: $store.selectedModel) {
                    ForEach(ParakeetModel.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 210)
                .disabled(store.isBusy || store.isRecording || store.isWarmingModel)

                Picker("Backend", selection: $store.selectedBackend) {
                    ForEach(ParakeetBackend.allCases) { backend in
                        Text(backend.label).tag(backend)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                .disabled(store.isBusy || store.isRecording || store.isWarmingModel)

                Button {
                    Task { await store.toggleRecording() }
                } label: {
                    Label(store.isRecording ? "Stop" : "Record", systemImage: store.isRecording ? "stop.fill" : "mic.fill")
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button {
                    Task { await store.transcribeLatestRecording() }
                } label: {
                    Label("Transcribe", systemImage: "text.bubble.fill")
                }
                .disabled(store.latestRecordingURL == nil || store.isBusy)
                .keyboardShortcut("t", modifiers: [.command])
            }
        }
        .onChange(of: store.selectedSessionID) { _, newValue in
            selectedSessionIDString = newValue?.uuidString
        }
        .onAppear {
            if let selectedSessionIDString, let id = UUID(uuidString: selectedSessionIDString) {
                store.selectedSessionID = id
            }
        }
        .task {
            await store.prepareTranscriber()
            store.refreshWorkerHealth()
        }
    }
}
