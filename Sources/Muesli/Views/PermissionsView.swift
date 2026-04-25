import SwiftUI

struct PermissionsView: View {
    @ObservedObject var permissions: PermissionManager
    let isFirstRun: Bool
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            VStack(spacing: 12) {
                PermissionRow(
                    title: "Microphone",
                    detail: "Required to record speech for local transcription.",
                    systemImage: "mic.fill",
                    state: permissions.microphone
                ) {
                    Task { await permissions.requestMicrophone() }
                } secondaryAction: {
                    permissions.openMicrophoneSettings()
                }

                PermissionRow(
                    title: "Accessibility",
                    detail: "Required for Command-Shift-D to paste into the app you were using.",
                    systemImage: "accessibility",
                    state: permissions.accessibility
                ) {
                    permissions.promptForAccessibility()
                } secondaryAction: {
                    permissions.openAccessibilitySettings()
                }
            }

            Divider()

            HStack {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    permissions.refresh()
                }

                Spacer()

                Button(isFirstRun ? "Continue" : "Done") {
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560)
        .onAppear {
            permissions.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: permissions.needsAttention ? "shield.lefthalf.filled.badge.checkmark" : "checkmark.shield.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(permissions.needsAttention ? .blue : .green)

            Text("Permissions")
                .font(.system(.title, design: .rounded, weight: .semibold))

            Text("Muesli needs microphone access for recording and Accessibility access for global dictation paste.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let state: PermissionState
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    PermissionStateBadge(state: state)
                }

                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 18)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    actionButtons
                }

                Menu("Actions") {
                    menuButtons
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var actionButtons: some View {
        if state.isGranted {
            Button("Open Settings", systemImage: "gearshape") {
                secondaryAction()
            }
        } else {
            Button(primaryTitle, systemImage: primaryIcon) {
                if state == .denied {
                    secondaryAction()
                } else {
                    primaryAction()
                }
            }

            Button("Settings", systemImage: "gearshape") {
                secondaryAction()
            }
        }
    }

    @ViewBuilder
    private var menuButtons: some View {
        Button(primaryTitle, systemImage: primaryIcon) {
            if state == .denied {
                secondaryAction()
            } else {
                primaryAction()
            }
        }
        Button("Open Settings", systemImage: "gearshape") {
            secondaryAction()
        }
    }

    private var primaryTitle: String {
        state == .denied ? "Open Settings" : "Allow"
    }

    private var primaryIcon: String {
        state == .denied ? "gearshape" : "checkmark.circle"
    }
}

private struct PermissionStateBadge: View {
    let state: PermissionState

    var body: some View {
        Label(state.label, systemImage: iconName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
    }

    private var iconName: String {
        switch state {
        case .granted:
            "checkmark.circle.fill"
        case .denied:
            "xmark.circle.fill"
        case .notDetermined:
            "questionmark.circle.fill"
        case .unknown:
            "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .granted:
            .green
        case .denied:
            .orange
        case .notDetermined:
            .blue
        case .unknown:
            .secondary
        }
    }
}
