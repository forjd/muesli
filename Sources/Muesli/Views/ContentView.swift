import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TranscriptionStore
    @SceneStorage("selectedSessionID") private var selectedSessionIDString: String?
    @AppStorage("hasSeenReadinessCheck") private var hasSeenReadinessCheck = false
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var permissions = PermissionManager()
    @State private var isShowingReadinessCheck = false

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

                Button {
                    Task { await store.toggleRecording() }
                } label: {
                    Label(store.isRecording ? "Stop" : "Record", systemImage: store.isRecording ? "stop.fill" : "mic.fill")
                }
                .labelStyle(.iconOnly)
                .help(store.isRecording ? "Stop recording" : "Start recording")
                .keyboardShortcut("r", modifiers: [.command])

                Button {
                    Task { await store.transcribeLatestRecording() }
                } label: {
                    Label("Transcribe", systemImage: "text.bubble.fill")
                }
                .labelStyle(.iconOnly)
                .help("Transcribe latest recording")
                .disabled(store.latestRecordingURL == nil || store.isBusy)
                .keyboardShortcut("t", modifiers: [.command])
            }

            ToolbarItem {
                Button {
                    permissions.refresh()
                    isShowingReadinessCheck = true
                } label: {
                    Label("Readiness", systemImage: readinessNeedsAttention ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                }
                .labelStyle(.iconOnly)
                .help("Review app readiness")
            }

            ToolbarItem {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
                .help("Open Muesli settings")
            }
        }
        .onChange(of: store.selectedSessionID) { _, newValue in
            selectedSessionIDString = newValue?.uuidString
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                permissions.refresh()
            }
        }
        .onAppear {
            permissions.refresh()
            if !hasSeenReadinessCheck {
                isShowingReadinessCheck = true
            }

            if let selectedSessionIDString, let id = UUID(uuidString: selectedSessionIDString) {
                store.selectedSessionID = id
            }
        }
        .sheet(isPresented: $isShowingReadinessCheck) {
            ReadinessCheckView(
                store: store,
                permissions: permissions,
                isFirstRun: !hasSeenReadinessCheck
            ) {
                hasSeenReadinessCheck = true
                permissions.refresh()
                isShowingReadinessCheck = false
            }
        }
        .task {
            await store.prepareTranscriber()
            store.refreshTranscriberHealth()
        }
    }

    private var readinessNeedsAttention: Bool {
        permissions.needsAttention || !store.modelLoadState.isReady
    }
}
