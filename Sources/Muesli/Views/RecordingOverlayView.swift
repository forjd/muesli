import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingOverlayController {
    private weak var store: TranscriptionStore?
    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []

    func configure(store: TranscriptionStore) {
        self.store = store
        cancellables.removeAll()

        store.$isRecording
            .removeDuplicates()
            .sink { [weak self] isRecording in
                if isRecording {
                    self?.show()
                } else {
                    self?.hide()
                }
            }
            .store(in: &cancellables)

        store.$recordingOverlayAnchor
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.positionVisiblePanel()
            }
            .store(in: &cancellables)
    }

    private func show() {
        guard let store else { return }
        let panel = panel ?? makePanel(store: store)
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func positionVisiblePanel() {
        guard let panel, panel.isVisible else { return }
        position(panel)
    }

    private func makePanel(store: TranscriptionStore) -> NSPanel {
        let rootView = RecordingOverlayView(store: store)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: rootView)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let size = panel.frame.size
        let y: CGFloat
        switch store?.recordingOverlayAnchor ?? .top {
        case .top:
            y = screenFrame.maxY - size.height - 22
        case .bottom:
            y = screenFrame.minY + 22
        }
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: y
        )
        panel.setFrameOrigin(origin)
    }
}

struct RecordingOverlayView: View {
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(.red.opacity(0.16))
                    .frame(width: 44, height: 44)

                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.red)

                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(formatElapsed(store.recordingElapsed))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: 78, alignment: .leading)

                    StatusBadge(title: store.dictationHotKeyMode.label, systemImage: "keyboard")

                    StatusBadge(
                        title: store.offlineMode ? "Offline" : store.privacyMode.shortLabel,
                        systemImage: store.offlineMode ? "wifi.slash" : "lock.shield",
                        tint: store.privacyMode.contentLeavesDevice ? .orange : .secondary
                    )
                }

                AudioLevelMeter(level: store.currentAudioLevel)
                    .frame(height: 7)
            }

            Spacer(minLength: 4)

            OverlayIconButton(systemName: "stop.fill", help: "Stop and transcribe") {
                Task { await store.toggleRecording() }
            }

            OverlayIconButton(systemName: "xmark", tint: .red, help: "Cancel recording") {
                store.cancelDictation()
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 500, height: 96)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.28))
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
    }

    private func formatElapsed(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed.rounded(.down)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct StatusBadge: View {
    let title: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.white.opacity(0.08), in: Capsule())
    }
}

private struct OverlayIconButton: View {
    let systemName: String
    var tint: Color = .primary
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 36)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help(help)
    }
}
