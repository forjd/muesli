import AppKit
import Carbon.HIToolbox
import SwiftUI

struct DictationHotKey: Codable, Hashable, Identifiable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    var id: String {
        "\(carbonModifiers)-\(keyCode)"
    }

    var label: String {
        let modifiers = modifierLabels.joined(separator: "-")
        if modifiers.isEmpty {
            return keyLabel
        }
        return "\(modifiers)-\(keyLabel)"
    }

    var keyEquivalent: KeyEquivalent? {
        guard let character = Self.keyEquivalentCharacters[keyCode] else { return nil }
        return KeyEquivalent(Character(character))
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []
        if carbonModifiers & UInt32(cmdKey) != 0 {
            modifiers.insert(.command)
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            modifiers.insert(.shift)
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            modifiers.insert(.option)
        }
        if carbonModifiers & UInt32(controlKey) != 0 {
            modifiers.insert(.control)
        }
        return modifiers
    }

    var isPreset: Bool {
        Self.presets.contains(self)
    }

    static let commandShiftD = DictationHotKey(keyCode: UInt32(kVK_ANSI_D), carbonModifiers: UInt32(cmdKey | shiftKey))
    static let commandShiftSpace = DictationHotKey(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey | shiftKey))
    static let commandOptionD = DictationHotKey(keyCode: UInt32(kVK_ANSI_D), carbonModifiers: UInt32(cmdKey | optionKey))
    static let commandOptionSpace = DictationHotKey(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey | optionKey))
    static let controlOptionD = DictationHotKey(keyCode: UInt32(kVK_ANSI_D), carbonModifiers: UInt32(controlKey | optionKey))
    static let controlOptionSpace = DictationHotKey(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | optionKey))

    static let presets: [DictationHotKey] = [
        .commandShiftD,
        .commandShiftSpace,
        .commandOptionD,
        .commandOptionSpace,
        .controlOptionD,
        .controlOptionSpace
    ]

    static func legacyPreset(rawValue: String) -> DictationHotKey? {
        switch rawValue {
        case "commandShiftD":
            .commandShiftD
        case "commandShiftSpace":
            .commandShiftSpace
        case "commandOptionD":
            .commandOptionD
        case "commandOptionSpace":
            .commandOptionSpace
        case "controlOptionD":
            .controlOptionD
        case "controlOptionSpace":
            .controlOptionSpace
        default:
            nil
        }
    }

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers & Self.supportedCarbonModifierMask
    }

    init?(event: NSEvent) {
        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard modifiers & Self.requiredCarbonModifierMask != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        return modifiers
    }

    private var modifierLabels: [String] {
        var labels: [String] = []
        if carbonModifiers & UInt32(cmdKey) != 0 {
            labels.append("Command")
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            labels.append("Shift")
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            labels.append("Option")
        }
        if carbonModifiers & UInt32(controlKey) != 0 {
            labels.append("Control")
        }
        return labels
    }

    private var keyLabel: String {
        Self.keyLabels[keyCode] ?? "Key \(keyCode)"
    }

    private static let supportedCarbonModifierMask = UInt32(cmdKey | shiftKey | optionKey | controlKey)
    private static let requiredCarbonModifierMask = UInt32(cmdKey | optionKey | controlKey)

    private static let keyLabels: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Escape): "Escape",
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab"
    ]

    private static let keyEquivalentCharacters: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "a",
        UInt32(kVK_ANSI_B): "b",
        UInt32(kVK_ANSI_C): "c",
        UInt32(kVK_ANSI_D): "d",
        UInt32(kVK_ANSI_E): "e",
        UInt32(kVK_ANSI_F): "f",
        UInt32(kVK_ANSI_G): "g",
        UInt32(kVK_ANSI_H): "h",
        UInt32(kVK_ANSI_I): "i",
        UInt32(kVK_ANSI_J): "j",
        UInt32(kVK_ANSI_K): "k",
        UInt32(kVK_ANSI_L): "l",
        UInt32(kVK_ANSI_M): "m",
        UInt32(kVK_ANSI_N): "n",
        UInt32(kVK_ANSI_O): "o",
        UInt32(kVK_ANSI_P): "p",
        UInt32(kVK_ANSI_Q): "q",
        UInt32(kVK_ANSI_R): "r",
        UInt32(kVK_ANSI_S): "s",
        UInt32(kVK_ANSI_T): "t",
        UInt32(kVK_ANSI_U): "u",
        UInt32(kVK_ANSI_V): "v",
        UInt32(kVK_ANSI_W): "w",
        UInt32(kVK_ANSI_X): "x",
        UInt32(kVK_ANSI_Y): "y",
        UInt32(kVK_ANSI_Z): "z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): " "
    ]
}

enum DictationHotKeyMode: String, CaseIterable, Codable, Hashable, Identifiable {
    case toggle
    case pushToTalk
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .toggle:
            "Toggle"
        case .pushToTalk:
            "Push to Talk"
        case .hybrid:
            "Hybrid"
        }
    }

    var detail: String {
        switch self {
        case .toggle:
            "Press once to start, press again to stop and paste."
        case .pushToTalk:
            "Hold to record, release to stop and paste."
        case .hybrid:
            "Tap to toggle, or hold to record until release."
        }
    }
}
