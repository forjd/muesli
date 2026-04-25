import Carbon.HIToolbox

struct DictationHotKeyTests {
    static func run() throws {
        try testDefaultHotKeyMapsToCommandShiftD()
        try testAllHotKeysRoundTripFromRawValue()
    }

    private static func testDefaultHotKeyMapsToCommandShiftD() throws {
        let hotKey = DictationHotKey.commandShiftD

        try expectEqual(hotKey.label, "Command-Shift-D")
        try expectEqual(hotKey.keyCode, UInt32(kVK_ANSI_D))
        try expectEqual(hotKey.carbonModifiers, UInt32(cmdKey | shiftKey))
        try expectEqual(hotKey.eventModifiers, [.command, .shift])
    }

    private static func testAllHotKeysRoundTripFromRawValue() throws {
        for hotKey in DictationHotKey.allCases {
            try expectEqual(DictationHotKey(rawValue: hotKey.rawValue), hotKey)
            try expect(!hotKey.label.isEmpty, "\(hotKey.rawValue) has an empty label")
        }
    }
}
