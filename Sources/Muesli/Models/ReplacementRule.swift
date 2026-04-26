import Foundation

struct ReplacementRule: Identifiable, Hashable, Codable {
    let id: UUID
    var find: String
    var replace: String
    var isEnabled: Bool

    init(id: UUID = UUID(), find: String, replace: String, isEnabled: Bool = true) {
        self.id = id
        self.find = find
        self.replace = replace
        self.isEnabled = isEnabled
    }
}

struct ReplacementRuleEngine {
    var rules: [ReplacementRule]

    func apply(to text: String) -> String {
        rules.reduce(text) { partial, rule in
            guard rule.isEnabled, !rule.find.isEmpty else { return partial }
            return partial.replacingOccurrences(of: rule.find, with: rule.replace)
        }
    }
}
