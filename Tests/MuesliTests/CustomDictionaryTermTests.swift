import Foundation

struct CustomDictionaryTermTests {
    static func run() throws {
        try testDictionaryTermsNormalizeCase()
        try testDisabledTermsAreIgnored()
        try testDefaultProfilesCoverCommonContexts()
        try testFuzzySuggestionsUseConservativeNearMatches()
        try testFuzzySuggestionsIgnoreShortAndDisabledTerms()
        try testProfileDecodingDefaultsFuzzyMatchingOff()
    }

    private static func testDictionaryTermsNormalizeCase() throws {
        let engine = CustomDictionaryEngine(terms: [
            CustomDictionaryTerm(value: "Muesli"),
            CustomDictionaryTerm(value: "API")
        ])

        try expectEqual(engine.apply(to: "muesli api"), "Muesli API")
    }

    private static func testDisabledTermsAreIgnored() throws {
        let engine = CustomDictionaryEngine(terms: [
            CustomDictionaryTerm(value: "Muesli", isEnabled: false)
        ])

        try expectEqual(engine.apply(to: "muesli"), "muesli")
    }

    private static func testDefaultProfilesCoverCommonContexts() throws {
        let names = CustomDictionaryProfile.defaultProfiles.map(\.name)

        try expect(names.contains("General"), "Expected a General dictionary profile")
        try expect(names.contains("Work"), "Expected a Work dictionary profile")
        try expect(names.contains("Code"), "Expected a Code dictionary profile")
        try expect(names.contains("Medical"), "Expected a Medical dictionary profile")
        try expect(names.contains("Legal"), "Expected a Legal dictionary profile")
    }

    private static func testFuzzySuggestionsUseConservativeNearMatches() throws {
        let engine = CustomDictionaryEngine(terms: [
            CustomDictionaryTerm(value: "Muesli"),
            CustomDictionaryTerm(value: "OpenAI")
        ])

        let suggestions = engine.fuzzySuggestions(in: "Muesl works with OpenAi and Muesl again.")

        try expectEqual(suggestions.count, 1)
        try expectEqual(suggestions[0].original, "Muesl")
        try expectEqual(suggestions[0].replacement, "Muesli")
        try expectEqual(suggestions[0].occurrenceCount, 2)
        try expectEqual(engine.apply(FuzzyDictionarySuggestion(
            sessionID: UUID(),
            profileID: CustomDictionaryProfile.generalID,
            original: "Muesl",
            replacement: "Muesli",
            occurrenceCount: 2,
            similarity: suggestions[0].similarity
        ), to: "Muesl works."), "Muesli works.")
    }

    private static func testFuzzySuggestionsIgnoreShortAndDisabledTerms() throws {
        let engine = CustomDictionaryEngine(terms: [
            CustomDictionaryTerm(value: "API"),
            CustomDictionaryTerm(value: "Muesli", isEnabled: false)
        ])

        try expect(engine.fuzzySuggestions(in: "APY and Muesley").isEmpty, "Expected no suggestions for short or disabled terms")
    }

    private static func testProfileDecodingDefaultsFuzzyMatchingOff() throws {
        let data = #"{"id":"00000000-0000-0000-0000-000000000101","name":"General","terms":[]}"#.data(using: .utf8)!
        let profile = try JSONDecoder().decode(CustomDictionaryProfile.self, from: data)

        try expectEqual(profile.fuzzyMatchingEnabled, false)
    }
}
