import Foundation

struct DictationFeedbackEventTests {
    static func run() throws {
        try testFeedbackKindsHaveIcons()
    }

    private static func testFeedbackKindsHaveIcons() throws {
        let kinds: [DictationFeedbackKind] = [.recordingStarted, .recordingStopped, .transcribing, .failed, .pasted]
        for kind in kinds {
            try expect(!kind.systemImage.isEmpty, "Expected feedback icon for \(kind)")
        }
    }
}
