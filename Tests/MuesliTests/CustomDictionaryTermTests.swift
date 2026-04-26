import Foundation

struct CustomDictionaryTermTests {
    static func run() throws {
        try testDictionaryTermsNormalizeCase()
        try testDisabledTermsAreIgnored()
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
}
