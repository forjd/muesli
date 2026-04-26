import Foundation

struct ReplacementRuleTests {
    static func run() throws {
        try testEnabledRulesApplyInOrder()
        try testDisabledAndEmptyRulesAreIgnored()
    }

    private static func testEnabledRulesApplyInOrder() throws {
        let engine = ReplacementRuleEngine(rules: [
            ReplacementRule(find: "brb", replace: "be right back"),
            ReplacementRule(find: "Muesley", replace: "Muesli")
        ])

        try expectEqual(engine.apply(to: "brb from Muesley"), "be right back from Muesli")
    }

    private static func testDisabledAndEmptyRulesAreIgnored() throws {
        let engine = ReplacementRuleEngine(rules: [
            ReplacementRule(find: "", replace: "ignored"),
            ReplacementRule(find: "hello", replace: "goodbye", isEnabled: false)
        ])

        try expectEqual(engine.apply(to: "hello"), "hello")
    }
}
