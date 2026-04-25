import Carbon.HIToolbox
import SwiftUI

enum DictationHotKey: String, CaseIterable, Codable, Hashable, Identifiable {
    case commandShiftD
    case commandShiftSpace
    case commandOptionD
    case commandOptionSpace
    case controlOptionD
    case controlOptionSpace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .commandShiftD:
            "Command-Shift-D"
        case .commandShiftSpace:
            "Command-Shift-Space"
        case .commandOptionD:
            "Command-Option-D"
        case .commandOptionSpace:
            "Command-Option-Space"
        case .controlOptionD:
            "Control-Option-D"
        case .controlOptionSpace:
            "Control-Option-Space"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .commandShiftD, .commandOptionD, .controlOptionD:
            UInt32(kVK_ANSI_D)
        case .commandShiftSpace, .commandOptionSpace, .controlOptionSpace:
            UInt32(kVK_Space)
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .commandShiftD, .commandShiftSpace:
            UInt32(cmdKey | shiftKey)
        case .commandOptionD, .commandOptionSpace:
            UInt32(cmdKey | optionKey)
        case .controlOptionD, .controlOptionSpace:
            UInt32(controlKey | optionKey)
        }
    }

    var keyEquivalent: KeyEquivalent {
        switch self {
        case .commandShiftD, .commandOptionD, .controlOptionD:
            "d"
        case .commandShiftSpace, .commandOptionSpace, .controlOptionSpace:
            " "
        }
    }

    var eventModifiers: SwiftUI.EventModifiers {
        switch self {
        case .commandShiftD, .commandShiftSpace:
            [.command, .shift]
        case .commandOptionD, .commandOptionSpace:
            [.command, .option]
        case .controlOptionD, .controlOptionSpace:
            [.control, .option]
        }
    }
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
