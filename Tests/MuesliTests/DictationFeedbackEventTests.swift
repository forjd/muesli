import Foundation

struct DictationFeedbackEventTests {
    static func run() throws {
        try testFeedbackKindsHaveIcons()
        try testFeedbackKindsHaveSounds()
    }

    private static func testFeedbackKindsHaveIcons() throws {
        let kinds: [DictationFeedbackKind] = [.recordingStarted, .recordingStopped, .transcribing, .failed, .pasted]
        for kind in kinds {
            try expect(!kind.systemImage.isEmpty, "Expected feedback icon for \(kind)")
        }
    }

    private static func testFeedbackKindsHaveSounds() throws {
        let kinds: [DictationFeedbackKind] = [.recordingStarted, .recordingStopped, .transcribing, .failed, .pasted]
        for kind in kinds {
            try expect(kind.systemSoundID > 0, "Expected feedback sound for \(kind)")
        }
    }
}
