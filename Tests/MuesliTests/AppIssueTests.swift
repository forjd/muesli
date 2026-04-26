import Foundation

struct AppIssueTests {
    static func run() throws {
        try testIssueTitlesAreSpecific()
        try testIssueIconsArePresent()
    }

    private static func testIssueTitlesAreSpecific() throws {
        try expectEqual(AppIssueKind.microphonePermission.title, "Microphone Permission Needed")
        try expectEqual(AppIssueKind.accessibilityPermission.title, "Accessibility Permission Needed")
        try expectEqual(AppIssueKind.modelLoad.title, "Model Could Not Load")
        try expectEqual(AppIssueKind.hotKey.title, "Hotkey Unavailable")
    }

    private static func testIssueIconsArePresent() throws {
        let kinds: [AppIssueKind] = [.microphonePermission, .accessibilityPermission, .modelLoad, .paste, .hotKey]
        for kind in kinds {
            try expect(!kind.systemImage.isEmpty, "Expected issue icon for \(kind)")
        }
    }
}
