import Foundation

struct AppIssue: Identifiable, Hashable {
    let id = UUID()
    var kind: AppIssueKind
    var detail: String

    var title: String {
        kind.title
    }

    var systemImage: String {
        kind.systemImage
    }
}

enum AppIssueKind: Hashable {
    case microphonePermission
    case accessibilityPermission
    case modelLoad
    case paste
    case hotKey

    var title: String {
        switch self {
        case .microphonePermission:
            "Microphone Permission Needed"
        case .accessibilityPermission:
            "Accessibility Permission Needed"
        case .modelLoad:
            "Model Could Not Load"
        case .paste:
            "Paste Needs Attention"
        case .hotKey:
            "Hotkey Unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .microphonePermission:
            "mic.slash.fill"
        case .accessibilityPermission:
            "accessibility"
        case .modelLoad:
            "cpu.fill"
        case .paste:
            "doc.on.clipboard"
        case .hotKey:
            "keyboard.badge.exclamationmark"
        }
    }
}
