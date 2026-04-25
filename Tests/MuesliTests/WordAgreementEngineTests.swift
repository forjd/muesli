struct WordAgreementEngineTests {
    static func run() throws {
        try testStablePrefixConfirmsWordsAndLeavesTrailingHypothesis()
        try testLowConfidencePassDoesNotConfirmWords()
    }

    private static func testStablePrefixConfirmsWordsAndLeavesTrailingHypothesis() throws {
        let engine = WordAgreementEngine(
            config: AgreementConfig(
                tokenConfirmationsNeeded: 1,
                minWordsToConfirm: 2,
                minPassConfidence: 0.1,
                minBoundaryConfidence: 0.1,
                trailingHypothesisWords: 1
            )
        )
        let words = [
            TimedWord(text: "Hello", startTime: 0, endTime: 0.3),
            TimedWord(text: "world", startTime: 0.3, endTime: 0.7),
            TimedWord(text: "again", startTime: 0.7, endTime: 1.0)
        ]

        _ = engine.process(words: words, confidence: 0.9)
        let result = engine.process(words: words, confidence: 0.9)

        try expectEqual(result.newlyConfirmedText, "Hello world")
        try expectEqual(result.fullText, "Hello world again")
        try expectEqual(engine.confirmedEndTime, 0.7)
        try expectEqual(engine.hypothesisStartTime, 0.7)
    }

    private static func testLowConfidencePassDoesNotConfirmWords() throws {
        let engine = WordAgreementEngine(
            config: AgreementConfig(
                tokenConfirmationsNeeded: 1,
                minWordsToConfirm: 2,
                minPassConfidence: 0.5,
                minBoundaryConfidence: 0.1,
                trailingHypothesisWords: 1
            )
        )
        let words = [
            TimedWord(text: "Hello", startTime: 0, endTime: 0.3),
            TimedWord(text: "world", startTime: 0.3, endTime: 0.7)
        ]

        _ = engine.process(words: words, confidence: 0.9)
        let result = engine.process(words: words, confidence: 0.2)

        try expectEqual(result.newlyConfirmedText, "")
        try expectEqual(result.fullText, "Hello world")
        try expectEqual(engine.confirmedEndTime, 0)
    }
}
