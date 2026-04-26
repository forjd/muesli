import Foundation

struct DictationStorageModeTests {
    static func run() throws {
        try testSaveRecordingAndTranscriptKeepsEverything()
        try testSaveTranscriptOnlyDeletesAudio()
        try testSaveNothingDeletesAudioAndTranscript()
    }

    private static func testSaveRecordingAndTranscriptKeepsEverything() throws {
        let mode = DictationStorageMode.saveRecordingAndTranscript
        try expect(!mode.deletesAudio, "Expected full save mode to keep audio")
        try expect(mode.keepsTranscript, "Expected full save mode to keep transcripts")
    }

    private static func testSaveTranscriptOnlyDeletesAudio() throws {
        let mode = DictationStorageMode.saveTranscriptOnly
        try expect(mode.deletesAudio, "Expected transcript-only mode to delete audio")
        try expect(mode.keepsTranscript, "Expected transcript-only mode to keep transcripts")
    }

    private static func testSaveNothingDeletesAudioAndTranscript() throws {
        let mode = DictationStorageMode.saveNothing
        try expect(mode.deletesAudio, "Expected save-nothing mode to delete audio")
        try expect(!mode.keepsTranscript, "Expected save-nothing mode to remove transcripts")
    }
}
