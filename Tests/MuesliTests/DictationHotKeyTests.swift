import Carbon.HIToolbox
import Foundation

struct DictationHotKeyTests {
    static func run() throws {
        try testDefaultHotKeyMapsToCommandShiftD()
        try testAllHotKeysRoundTripFromRawValue()
        try testLegacyPresetRawValuesResolve()
        try testAllHotKeyModesRoundTripFromRawValue()
    }

    private static func testDefaultHotKeyMapsToCommandShiftD() throws {
        let hotKey = DictationHotKey.commandShiftD

        try expectEqual(hotKey.label, "Command-Shift-D")
        try expectEqual(hotKey.keyCode, UInt32(kVK_ANSI_D))
        try expectEqual(hotKey.carbonModifiers, UInt32(cmdKey | shiftKey))
        try expectEqual(hotKey.eventModifiers, [.command, .shift])
    }

    private static func testAllHotKeysRoundTripFromRawValue() throws {
        for hotKey in DictationHotKey.presets {
            let data = try JSONEncoder().encode(hotKey)
            let decoded = try JSONDecoder().decode(DictationHotKey.self, from: data)
            try expectEqual(decoded, hotKey)
            try expect(!hotKey.label.isEmpty, "\(hotKey.id) has an empty label")
        }
    }

    private static func testLegacyPresetRawValuesResolve() throws {
        try expectEqual(DictationHotKey.legacyPreset(rawValue: "commandShiftD"), .commandShiftD)
        try expectEqual(DictationHotKey.legacyPreset(rawValue: "commandOptionSpace"), .commandOptionSpace)
        try expect(DictationHotKey.legacyPreset(rawValue: "unknown") == nil, "Unknown legacy preset should be nil")
    }

    private static func testAllHotKeyModesRoundTripFromRawValue() throws {
        for mode in DictationHotKeyMode.allCases {
            try expectEqual(DictationHotKeyMode(rawValue: mode.rawValue), mode)
            try expect(!mode.label.isEmpty, "\(mode.rawValue) has an empty label")
            try expect(!mode.detail.isEmpty, "\(mode.rawValue) has an empty detail")
        }
    }
}
