import Foundation

struct MuesliCLIContractTests {
    static func run() throws {
        try testSpecIncludesVersionAndCommands()
        try testSuccessEnvelopeIncludesWarnings()
        try testErrorEnvelopeIncludesFix()
    }

    private static func testSpecIncludesVersionAndCommands() throws {
        let object = try jsonObject(from: MuesliCLIContract.specData())
        try expectEqual(object["schemaVersion"] as? String, "1.0")

        let commands = try expectArray(object["commands"], "commands")
        let names = commands.compactMap { ($0 as? [String: Any])?["name"] as? String }
        try expect(names.contains("spec"), "Spec command is missing")
        try expect(names.contains("transcribe"), "Transcribe command is missing")
        try expect(names.contains("export"), "Export command is missing")
    }

    private static func testSuccessEnvelopeIncludesWarnings() throws {
        let data = try MuesliCLIContract.successData(
            command: "transcribe",
            result: ["count": 1],
            warnings: [MuesliCLIWarning(code: "skipped", message: "Skipped one file.", fix: "Check the path.")]
        )
        let object = try jsonObject(from: data)

        try expectEqual(object["ok"] as? Bool, true)
        try expectEqual(object["command"] as? String, "transcribe")
        try expectEqual(try expectArray(object["warnings"], "warnings").count, 1)
    }

    private static func testErrorEnvelopeIncludesFix() throws {
        let object = try jsonObject(from: MuesliCLIContract.errorData(command: "export", message: "No output directory.", fix: "Pass --output."))
        let error = try expectDictionary(object["error"], "error")

        try expectEqual(object["ok"] as? Bool, false)
        try expectEqual(error["fix"] as? String, "Pass --output.")
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestFailure("Expected JSON object")
        }
        return object
    }

    private static func expectArray(_ value: Any?, _ name: String) throws -> [Any] {
        guard let array = value as? [Any] else {
            throw TestFailure("Expected \(name) array")
        }
        return array
    }

    private static func expectDictionary(_ value: Any?, _ name: String) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw TestFailure("Expected \(name) dictionary")
        }
        return dictionary
    }
}
