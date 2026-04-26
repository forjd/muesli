import Foundation

enum RecordingOverlayAnchor: String, CaseIterable, Identifiable {
    case top
    case bottom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top:
            "Top"
        case .bottom:
            "Bottom"
        }
    }
}
