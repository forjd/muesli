import Foundation

struct CustomDictionaryTerm: Identifiable, Hashable, Codable {
    let id: UUID
    var value: String
    var isEnabled: Bool

    init(id: UUID = UUID(), value: String, isEnabled: Bool = true) {
        self.id = id
        self.value = value
        self.isEnabled = isEnabled
    }
}

struct CustomDictionaryProfile: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var terms: [CustomDictionaryTerm]
    var fuzzyMatchingEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        terms: [CustomDictionaryTerm] = [],
        fuzzyMatchingEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.terms = terms
        self.fuzzyMatchingEnabled = fuzzyMatchingEnabled
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case terms
        case fuzzyMatchingEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        terms = try container.decodeIfPresent([CustomDictionaryTerm].self, forKey: .terms) ?? []
        fuzzyMatchingEnabled = try container.decodeIfPresent(Bool.self, forKey: .fuzzyMatchingEnabled) ?? false
    }

    static let generalID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!

    static var defaultProfiles: [CustomDictionaryProfile] {
        [
            CustomDictionaryProfile(id: generalID, name: "General"),
            CustomDictionaryProfile(name: "Work"),
            CustomDictionaryProfile(name: "Code"),
            CustomDictionaryProfile(name: "Medical"),
            CustomDictionaryProfile(name: "Legal")
        ]
    }
}

struct FuzzyDictionarySuggestion: Identifiable, Hashable {
    let id: UUID
    let sessionID: TranscriptSession.ID
    let profileID: CustomDictionaryProfile.ID
    let original: String
    let replacement: String
    let occurrenceCount: Int
    let similarity: Double

    init(
        id: UUID = UUID(),
        sessionID: TranscriptSession.ID,
        profileID: CustomDictionaryProfile.ID,
        original: String,
        replacement: String,
        occurrenceCount: Int,
        similarity: Double
    ) {
        self.id = id
        self.sessionID = sessionID
        self.profileID = profileID
        self.original = original
        self.replacement = replacement
        self.occurrenceCount = occurrenceCount
        self.similarity = similarity
    }
}

struct FuzzyDictionarySuggestionCandidate: Hashable {
    var original: String
    var replacement: String
    var occurrenceCount: Int
    var similarity: Double
}

struct CustomDictionaryEngine {
    var terms: [CustomDictionaryTerm]

    func apply(to text: String) -> String {
        terms.reduce(text) { partial, term in
            guard term.isEnabled, !term.value.isEmpty else { return partial }
            return partial.replacingOccurrences(
                of: term.value,
                with: term.value,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
        }
    }

    func fuzzySuggestions(in text: String) -> [FuzzyDictionarySuggestionCandidate] {
        let enabledTerms = terms
            .filter { $0.isEnabled }
            .map(\.value)
            .filter { Self.normalized($0).count >= 5 && !$0.contains(where: \.isWhitespace) }

        guard !enabledTerms.isEmpty else { return [] }

        let words = Self.words(in: text)
        var suggestions: [String: FuzzyDictionarySuggestionCandidate] = [:]

        for word in words {
            let normalizedWord = Self.normalized(word)
            guard normalizedWord.count >= 5 else { continue }

            for term in enabledTerms {
                let normalizedTerm = Self.normalized(term)
                guard normalizedWord != normalizedTerm else { continue }
                guard normalizedWord.first == normalizedTerm.first else { continue }

                let distance = Self.levenshteinDistance(normalizedWord, normalizedTerm)
                guard distance <= Self.maximumDistance(forLength: normalizedTerm.count) else { continue }

                let longestLength = max(normalizedWord.count, normalizedTerm.count)
                let similarity = 1 - (Double(distance) / Double(longestLength))
                guard similarity >= 0.82 else { continue }

                let key = "\(word.lowercased())\u{0}\(term.lowercased())"
                if var existing = suggestions[key] {
                    existing.occurrenceCount += 1
                    existing.similarity = max(existing.similarity, similarity)
                    suggestions[key] = existing
                } else {
                    suggestions[key] = FuzzyDictionarySuggestionCandidate(
                        original: word,
                        replacement: term,
                        occurrenceCount: 1,
                        similarity: similarity
                    )
                }
            }
        }

        return suggestions.values.sorted {
            if $0.similarity == $1.similarity {
                return $0.original.localizedCaseInsensitiveCompare($1.original) == .orderedAscending
            }
            return $0.similarity > $1.similarity
        }
    }

    func apply(_ suggestion: FuzzyDictionarySuggestion, to text: String) -> String {
        guard !suggestion.original.isEmpty else { return text }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: suggestion.original))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: suggestion.replacement)
        )
    }

    private static func words(in text: String) -> [String] {
        var words: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .localized]) { substring, _, _, _ in
            guard let substring else { return }
            words.append(substring)
        }
        return words
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func maximumDistance(forLength length: Int) -> Int {
        switch length {
        case 0...4:
            0
        case 5...7:
            1
        default:
            2
        }
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let lhs = Array(lhs)
        let rhs = Array(rhs)

        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var previous = Array(0...rhs.count)
        var current = Array(repeating: 0, count: rhs.count + 1)

        for lhsIndex in 1...lhs.count {
            current[0] = lhsIndex

            for rhsIndex in 1...rhs.count {
                let substitutionCost = lhs[lhsIndex - 1] == rhs[rhsIndex - 1] ? 0 : 1
                current[rhsIndex] = min(
                    previous[rhsIndex] + 1,
                    current[rhsIndex - 1] + 1,
                    previous[rhsIndex - 1] + substitutionCost
                )
            }

            swap(&previous, &current)
        }

        return previous[rhs.count]
    }
}
