import FluidAudio
import Foundation

struct TimedWord: Hashable {
    let text: String
    let normalizedText: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float

    init(text: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Float = 1) {
        self.text = text
        self.normalizedText = Self.normalize(text)
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }

    private static func normalize(_ text: String) -> String {
        String(text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AgreementConfig {
    var tokenConfirmationsNeeded = 2
    var minWordsToConfirm = 2
    var minPassConfidence: Float = 0.12
    var minBoundaryConfidence: Float = 0.35
    var trailingHypothesisWords = 1
}

struct AgreementResult {
    let fullText: String
    let newlyConfirmedText: String
    let words: [TimedWord]
}

final class WordAgreementEngine {
    private let config: AgreementConfig
    private var confirmedWords: [TimedWord] = []
    private var previousWords: [TimedWord] = []
    private var consecutiveAgreementCount = 0
    private var isFirstPass = true

    private(set) var confirmedEndTime: TimeInterval = 0
    private(set) var hypothesisStartTime: TimeInterval = 0

    init(config: AgreementConfig = AgreementConfig()) {
        self.config = config
    }

    func reset() {
        confirmedWords = []
        previousWords = []
        consecutiveAgreementCount = 0
        isFirstPass = true
        confirmedEndTime = 0
        hypothesisStartTime = 0
    }

    func process(words: [TimedWord], confidence: Float) -> AgreementResult {
        guard !words.isEmpty else {
            return makeResult(hypothesis: [], newlyConfirmed: [])
        }

        if isFirstPass {
            isFirstPass = false
            previousWords = words
            hypothesisStartTime = words.first?.startTime ?? confirmedEndTime
            return makeResult(hypothesis: words, newlyConfirmed: [])
        }

        if confidence < config.minPassConfidence {
            consecutiveAgreementCount = 0
            previousWords = words
            hypothesisStartTime = words.first?.startTime ?? confirmedEndTime
            return makeResult(hypothesis: words, newlyConfirmed: [])
        }

        let prefixCount = commonPrefixCount(current: words, previous: previousWords)
        previousWords = words

        guard prefixCount >= config.minWordsToConfirm else {
            consecutiveAgreementCount = 0
            hypothesisStartTime = words.first?.startTime ?? confirmedEndTime
            return makeResult(hypothesis: words, newlyConfirmed: [])
        }

        consecutiveAgreementCount += 1
        guard consecutiveAgreementCount >= config.tokenConfirmationsNeeded else {
            return makeResult(hypothesis: words, newlyConfirmed: [])
        }

        let confirmCount = confirmationCount(from: Array(words.prefix(prefixCount)))
        guard confirmCount > 0 else {
            return makeResult(hypothesis: words, newlyConfirmed: [])
        }

        let newlyConfirmed = Array(words.prefix(confirmCount))
        let hypothesis = Array(words.dropFirst(confirmCount))

        confirmedWords.append(contentsOf: newlyConfirmed)
        confirmedEndTime = newlyConfirmed.last?.endTime ?? confirmedEndTime
        hypothesisStartTime = hypothesis.first?.startTime ?? confirmedEndTime

        consecutiveAgreementCount = hypothesis.isEmpty ? 0 : 1
        previousWords = hypothesis
        isFirstPass = hypothesis.isEmpty

        return makeResult(hypothesis: hypothesis, newlyConfirmed: newlyConfirmed)
    }

    static func mergeTokensToWords(_ timings: [TokenTiming], timeOffset: TimeInterval = 0) -> [TimedWord] {
        var words: [TimedWord] = []
        var text = ""
        var start: TimeInterval = 0
        var end: TimeInterval = 0
        var confidences: [Float] = []

        for timing in timings {
            let token = timing.token
            if token.hasPrefix("▁") || token.hasPrefix(" ") {
                appendCurrentWord(&words, text: &text, start: start, end: end, confidences: confidences, timeOffset: timeOffset)
                text = token.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "▁", with: "")
                start = timing.startTime
                end = timing.endTime
                confidences = [timing.confidence]
            } else {
                if text.isEmpty {
                    start = timing.startTime
                }
                text += token
                end = timing.endTime
                confidences.append(timing.confidence)
            }
        }

        appendCurrentWord(&words, text: &text, start: start, end: end, confidences: confidences, timeOffset: timeOffset)
        return words
    }

    private static func appendCurrentWord(
        _ words: inout [TimedWord],
        text: inout String,
        start: TimeInterval,
        end: TimeInterval,
        confidences: [Float],
        timeOffset: TimeInterval
    ) {
        guard !text.isEmpty else { return }
        let confidence = confidences.isEmpty ? 1 : confidences.reduce(0, +) / Float(confidences.count)
        words.append(TimedWord(text: text, startTime: start + timeOffset, endTime: end + timeOffset, confidence: confidence))
        text = ""
    }

    private func commonPrefixCount(current: [TimedWord], previous: [TimedWord]) -> Int {
        let limit = min(current.count, previous.count)
        for index in 0..<limit where current[index].normalizedText != previous[index].normalizedText {
            return index
        }
        return limit
    }

    private func confirmationCount(from words: [TimedWord]) -> Int {
        guard words.count >= config.minWordsToConfirm else { return 0 }

        let boundaryWords = Array(words.suffix(2))
        let minConfidence = boundaryWords.map(\.confidence).min() ?? 1
        guard minConfidence >= config.minBoundaryConfidence else { return 0 }

        if let punctuationIndex = words.indices.dropLast(1).last(where: { index in
            guard let last = words[index].text.last else { return false }
            return [".", "!", "?", ";"].contains(last)
        }) {
            return max(config.minWordsToConfirm, punctuationIndex + 1)
        }

        return max(0, words.count - config.trailingHypothesisWords)
    }

    private func makeResult(hypothesis: [TimedWord], newlyConfirmed: [TimedWord]) -> AgreementResult {
        let words = confirmedWords + hypothesis
        return AgreementResult(
            fullText: words.map(\.text).joined(separator: " "),
            newlyConfirmedText: newlyConfirmed.map(\.text).joined(separator: " "),
            words: words
        )
    }
}
