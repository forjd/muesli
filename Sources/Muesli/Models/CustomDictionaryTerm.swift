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
}
