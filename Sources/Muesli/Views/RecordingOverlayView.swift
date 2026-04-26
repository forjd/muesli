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

    private func makePanel(store: TranscriptionStore) -> NSPanel {
        let rootView = RecordingOverlayView(store: store)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 118),
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
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height - 22
        )
        panel.setFrameOrigin(origin)
    }
}

struct RecordingOverlayView: View {
    @ObservedObject var store: TranscriptionStore

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundStyle(.red)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(formatElapsed(store.recordingElapsed))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()

                    Text(store.dictationHotKeyMode.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(store.offlineMode ? "Offline" : store.privacyMode.shortLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(store.privacyMode.contentLeavesDevice ? .orange : .secondary)
                }

                AudioLevelMeter(level: store.currentAudioLevel)
                    .frame(width: 210)
            }

            Spacer(minLength: 8)

            Button {
                Task { await store.toggleRecording() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .labelStyle(.iconOnly)
            .help("Stop and transcribe")

            Button(role: .destructive) {
                store.cancelDictation()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .labelStyle(.iconOnly)
            .help("Cancel recording")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 420, height: 118)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func formatElapsed(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed.rounded(.down)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
