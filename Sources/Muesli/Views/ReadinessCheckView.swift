import SwiftUI

struct ReadinessCheckView: View {
    @ObservedObject var store: TranscriptionStore
    @ObservedObject var permissions: PermissionManager
    let isFirstRun: Bool
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            VStack(spacing: 12) {
                ReadinessRow(
                    title: "Microphone",
                    detail: "Required to record speech for local transcription.",
                    systemImage: "mic.fill",
                    state: permissionReadinessState(permissions.microphone),
                    primaryTitle: permissions.microphone == .denied ? "Open Settings" : "Allow",
                    primarySystemImage: permissions.microphone == .denied ? "gearshape" : "checkmark.circle",
                    secondaryTitle: "Settings",
                    secondarySystemImage: "gearshape"
                ) {
                    if permissions.microphone == .denied {
                        permissions.openMicrophoneSettings()
                    } else {
                        Task { await permissions.requestMicrophone() }
                    }
                } secondaryAction: {
                    permissions.openMicrophoneSettings()
                }

                ReadinessRow(
                    title: "Accessibility",
                    detail: "Required to paste dictation into the app you were using.",
                    systemImage: "accessibility",
                    state: permissionReadinessState(permissions.accessibility),
                    primaryTitle: permissions.accessibility == .granted ? "Open Settings" : "Allow",
                    primarySystemImage: permissions.accessibility == .granted ? "gearshape" : "checkmark.circle",
                    secondaryTitle: permissions.accessibility == .granted ? nil : "Settings",
                    secondarySystemImage: "gearshape"
                ) {
                    if permissions.accessibility == .granted {
                        permissions.openAccessibilitySettings()
                    } else {
                        permissions.promptForAccessibility()
                    }
                } secondaryAction: {
                    permissions.openAccessibilitySettings()
                }

                ReadinessRow(
                    title: store.selectedModel.label,
                    detail: store.modelLoadState.detail,
                    systemImage: "cpu",
                    state: modelReadinessState,
                    primaryTitle: modelPrimaryTitle,
                    primarySystemImage: modelPrimaryIcon,
                    secondaryTitle: nil,
                    secondarySystemImage: nil
                ) {
                    if case .downloadRequired = store.modelLoadState {
                        store.offlineMode = false
                        Task { await store.prepareTranscriber() }
                    } else {
                        Task { await store.prepareTranscriber() }
                    }
                } secondaryAction: {}

                ReadinessRow(
                    title: "Speaker Diarization",
                    detail: store.diarizationModelLoadState.detail,
                    systemImage: "person.2",
                    state: diarizationReadinessState,
                    primaryTitle: diarizationPrimaryTitle,
                    primarySystemImage: diarizationPrimaryIcon,
                    secondaryTitle: nil,
                    secondarySystemImage: nil
                ) {
                    if case .downloadRequired = store.diarizationModelLoadState {
                        store.offlineMode = false
                        Task { await store.prepareDiarizer() }
                    } else {
                        Task { await store.prepareDiarizer() }
                    }
                } secondaryAction: {}

                ReadinessRow(
                    title: store.privacyMode.label,
                    detail: store.privacyMode.detail,
                    systemImage: store.offlineMode ? "wifi.slash" : (store.privacyMode.contentLeavesDevice ? "network" : "lock.shield"),
                    state: .ready(store.offlineMode ? "Offline" : (store.privacyMode.contentLeavesDevice ? "Remote" : "Local")),
                    primaryTitle: nil,
                    primarySystemImage: nil,
                    secondaryTitle: nil,
                    secondarySystemImage: nil
                ) {} secondaryAction: {}

                ReadinessRow(
                    title: "Dictation Hotkey",
                    detail: "\(store.dictationHotKey.label) · \(store.dictationHotKeyMode.label)",
                    systemImage: "keyboard",
                    state: .ready("Configured"),
                    primaryTitle: "Settings",
                    primarySystemImage: "gearshape",
                    secondaryTitle: nil,
                    secondarySystemImage: nil
                ) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } secondaryAction: {}
            }

            if isFirstRun {
                firstRunSetup
            }

            Divider()

            HStack {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    permissions.refresh()
                    store.refreshTranscriberHealth()
                }

                Spacer()

                Button(isFirstRun ? "Continue" : "Done") {
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 620)
        .onAppear {
            permissions.refresh()
            store.refreshTranscriberHealth()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: needsAttention ? "checklist.unchecked" : "checkmark.seal.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(needsAttention ? .blue : .green)

            Text(isFirstRun ? "Set Up Muesli" : "Ready Check")
                .font(.system(.title, design: .rounded, weight: .semibold))

            Text(isFirstRun ? "Grant permissions, choose local models, and confirm dictation behavior before using the app." : "Confirm Muesli can record audio, load the local model, and paste dictation with the configured hotkey.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var firstRunSetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Text("Setup")
                .font(.headline)

            Picker("Default model", selection: $store.selectedModel) {
                ForEach(ParakeetModel.allCases) { model in
                    Text(model.label).tag(model)
                }
            }
            .disabled(store.isWarmingModel)

            Toggle("Offline mode after models are cached", isOn: $store.offlineMode)

            Picker("Hotkey behavior", selection: $store.dictationHotKeyMode) {
                ForEach(DictationHotKeyMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Picker("Hotkey", selection: $store.dictationHotKey) {
                ForEach(DictationHotKey.presets) { hotKey in
                    Text(hotKey.label).tag(hotKey)
                }
            }

            HStack {
                Button("Prepare Selected Model", systemImage: "arrow.down.circle") {
                    Task { await store.prepareTranscriber() }
                }
                .disabled(store.isWarmingModel || store.modelLoadState.isReady)

                Button("Manage Models", systemImage: "cpu") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }

            Text("Model downloads happen once. After the selected model is cached, offline mode can stay on for local-only dictation.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var needsAttention: Bool {
        permissions.needsAttention || !store.modelLoadState.isReady
    }

    private var diarizationReadinessState: ReadinessState {
        switch store.diarizationModelLoadState {
        case .ready:
            .ready("Ready")
        case .loadingCached, .downloading:
            .working("Loading")
        case .failed:
            .blocked("Failed")
        case .downloadRequired:
            .blocked("Download")
        case .idle:
            .attention("Optional")
        }
    }

    private var diarizationPrimaryTitle: String? {
        switch store.diarizationModelLoadState {
        case .ready:
            nil
        case .loadingCached, .downloading:
            "Loading"
        case .downloadRequired:
            store.offlineMode ? "Allow Download" : "Download"
        case .failed:
            "Retry"
        case .idle:
            "Load"
        }
    }

    private var diarizationPrimaryIcon: String? {
        switch store.diarizationModelLoadState {
        case .ready:
            nil
        case .loadingCached, .downloading:
            "hourglass"
        case .downloadRequired:
            "arrow.down.circle"
        case .failed:
            "arrow.clockwise"
        case .idle:
            "arrow.down.circle"
        }
    }

    private var modelReadinessState: ReadinessState {
        switch store.modelLoadState {
        case .ready:
            .ready("Ready")
        case .loadingCached, .downloading:
            .working("Loading")
        case .failed:
            .blocked("Failed")
        case .downloadRequired:
            .blocked("Download")
        case .idle:
            .attention("Not Loaded")
        }
    }

    private var modelPrimaryTitle: String? {
        switch store.modelLoadState {
        case .ready:
            nil
        case .loadingCached, .downloading:
            "Loading"
        case .downloadRequired:
            store.offlineMode ? "Allow Download" : "Download"
        case .failed:
            "Retry"
        case .idle:
            "Load"
        }
    }

    private var modelPrimaryIcon: String? {
        switch store.modelLoadState {
        case .ready:
            nil
        case .loadingCached, .downloading:
            "hourglass"
        case .downloadRequired:
            "arrow.down.circle"
        case .failed:
            "arrow.clockwise"
        case .idle:
            "arrow.down.circle"
        }
    }

    private func permissionReadinessState(_ state: PermissionState) -> ReadinessState {
        switch state {
        case .granted:
            .ready("Allowed")
        case .denied:
            .blocked("Blocked")
        case .notDetermined:
            .attention("Not Set")
        case .unknown:
            .attention("Unknown")
        }
    }
}

private struct ReadinessRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let state: ReadinessState
    let primaryTitle: String?
    let primarySystemImage: String?
    let secondaryTitle: String?
    let secondarySystemImage: String?
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    ReadinessBadge(state: state)
                }

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    actionButtons
                }

                Menu("Actions") {
                    actionMenu
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let primaryTitle {
            Button(primaryTitle, systemImage: primarySystemImage ?? "checkmark.circle") {
                primaryAction()
            }
            .disabled(state == .working("Loading"))
        }

        if let secondaryTitle {
            Button(secondaryTitle, systemImage: secondarySystemImage ?? "gearshape") {
                secondaryAction()
            }
        }
    }

    @ViewBuilder
    private var actionMenu: some View {
        if let primaryTitle {
            Button(primaryTitle, systemImage: primarySystemImage ?? "checkmark.circle") {
                primaryAction()
            }
            .disabled(state == .working("Loading"))
        }

        if let secondaryTitle {
            Button(secondaryTitle, systemImage: secondarySystemImage ?? "gearshape") {
                secondaryAction()
            }
        }
    }
}

private struct ReadinessBadge: View {
    let state: ReadinessState

    var body: some View {
        Label(state.label, systemImage: state.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.color)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(state.color.opacity(0.16), in: Capsule())
    }
}

private enum ReadinessState: Hashable {
    case ready(String)
    case working(String)
    case attention(String)
    case blocked(String)

    var label: String {
        switch self {
        case let .ready(label), let .working(label), let .attention(label), let .blocked(label):
            label
        }
    }

    var systemImage: String {
        switch self {
        case .ready:
            "checkmark.circle.fill"
        case .working:
            "hourglass.circle.fill"
        case .attention:
            "exclamationmark.circle.fill"
        case .blocked:
            "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready:
            .green
        case .working:
            .blue
        case .attention:
            .orange
        case .blocked:
            .red
        }
    }
}
