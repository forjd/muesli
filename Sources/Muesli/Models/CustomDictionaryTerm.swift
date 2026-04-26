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

    init(id: UUID = UUID(), name: String, terms: [CustomDictionaryTerm] = []) {
        self.id = id
        self.name = name
        self.terms = terms
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
