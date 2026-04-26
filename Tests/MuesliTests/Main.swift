@main
struct MuesliTestRunner {
    static func main() throws {
        try DictationHotKeyTests.run()
        try RetentionPolicyTests.run()
        try SecureStorageTests.run()
        try SessionPersistenceTests.run()
        try TranscriptExporterTests.run()
        try WordAgreementEngineTests.run()
        print("MuesliTests passed")
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

func expect(_ condition: Bool, _ message: String) throws {
    guard condition else {
        throw TestFailure(message)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) throws {
    guard actual == expected else {
        throw TestFailure("Expected \(expected), got \(actual) at \(file):\(line)")
    }
}
