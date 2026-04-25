import AppKit
import ApplicationServices
import AVFoundation
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var microphone: PermissionState = .unknown
    @Published private(set) var accessibility: PermissionState = .unknown

    var needsAttention: Bool {
        microphone != .granted || accessibility != .granted
    }

    func refresh() {
        microphone = Self.microphoneState()
        accessibility = AXIsProcessTrusted() ? .granted : .notDetermined
    }

    func requestMicrophone() async {
        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        microphone = granted ? .granted : .denied
    }

    func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibility = AXIsProcessTrustedWithOptions(options) ? .granted : .notDetermined
    }

    func openMicrophoneSettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func openAccessibilitySettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func openSettingsPane(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func microphoneState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            .granted
        case .denied, .restricted:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .unknown
        }
    }
}

enum PermissionState: Hashable {
    case unknown
    case notDetermined
    case granted
    case denied

    var label: String {
        switch self {
        case .unknown:
            "Unknown"
        case .notDetermined:
            "Not Set"
        case .granted:
            "Allowed"
        case .denied:
            "Blocked"
        }
    }

    var isGranted: Bool {
        self == .granted
    }
}
