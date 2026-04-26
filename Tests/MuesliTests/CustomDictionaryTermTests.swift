import Foundation

struct CustomDictionaryTermTests {
    static func run() throws {
        try testDictionaryTermsNormalizeCase()
        try testDisabledTermsAreIgnored()
        try testDefaultProfilesCoverCommonContexts()
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
}
