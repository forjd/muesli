import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TranscriptionStore
    @SceneStorage("selectedSessionID") private var selectedSessionIDString: String?
    @AppStorage("hasSeenPermissionsOnboarding") private var hasSeenPermissionsOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var permissions = PermissionManager()
    @State private var isShowingPermissions = false

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
                .keyboardShortcut("r", modifiers: [.command])

                Button {
                    Task { await store.transcribeLatestRecording() }
                } label: {
                    Label("Transcribe", systemImage: "text.bubble.fill")
                }
                .disabled(store.latestRecordingURL == nil || store.isBusy)
                .keyboardShortcut("t", modifiers: [.command])
            }

            ToolbarItem {
                Button {
                    permissions.refresh()
                    isShowingPermissions = true
                } label: {
                    Label("Permissions", systemImage: permissions.needsAttention ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                }
                .help("Review microphone and Accessibility permissions")
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
            if !hasSeenPermissionsOnboarding {
                isShowingPermissions = true
            }

            if let selectedSessionIDString, let id = UUID(uuidString: selectedSessionIDString) {
                store.selectedSessionID = id
            }
        }
        .sheet(isPresented: $isShowingPermissions) {
            PermissionsView(
                permissions: permissions,
                isFirstRun: !hasSeenPermissionsOnboarding
            ) {
                hasSeenPermissionsOnboarding = true
                permissions.refresh()
                isShowingPermissions = false
            }
        }
        .task {
            await store.prepareTranscriber()
            store.refreshTranscriberHealth()
        }
    }
}
