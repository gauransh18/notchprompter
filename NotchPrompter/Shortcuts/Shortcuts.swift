import AppKit
import Carbon.HIToolbox
import Observation

// MARK: - Combo

struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt16
    /// Subset of `NSEvent.ModifierFlags.deviceIndependentFlagsMask`.
    var modifiers: UInt

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    var isValid: Bool {
        // A bare letter would swallow typing everywhere; require a real modifier.
        flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
    }

    var display: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        text += KeyCodeNames.name(for: keyCode)
        return text
    }
}

// MARK: - Actions

enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case togglePlay
    case toggleVisible
    case restart
    case speedUp
    case speedDown
    case nextLine
    case previousLine
    case toggleVoice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .togglePlay: return "Play / Pause"
        case .toggleVisible: return "Show / Hide Prompter"
        case .restart: return "Back to Start"
        case .speedUp: return "Scroll Faster"
        case .speedDown: return "Scroll Slower"
        case .nextLine: return "Nudge Down"
        case .previousLine: return "Nudge Up"
        case .toggleVoice: return "Toggle Voice Follow"
        }
    }

    var symbol: String {
        switch self {
        case .togglePlay: return "playpause"
        case .toggleVisible: return "eye"
        case .restart: return "arrow.counterclockwise"
        case .speedUp: return "hare"
        case .speedDown: return "tortoise"
        case .nextLine: return "arrow.down"
        case .previousLine: return "arrow.up"
        case .toggleVoice: return "waveform"
        }
    }

    var hotKeyID: UInt32 {
        UInt32(ShortcutAction.allCases.firstIndex(of: self)! + 1)
    }

    static let defaults: [ShortcutAction: KeyCombo] = {
        let optionCommand = NSEvent.ModifierFlags([.option, .command]).rawValue
        return [
            .togglePlay: KeyCombo(keyCode: UInt16(kVK_ANSI_P), modifiers: optionCommand),
            .toggleVisible: KeyCombo(keyCode: UInt16(kVK_ANSI_N), modifiers: optionCommand),
            .restart: KeyCombo(keyCode: UInt16(kVK_ANSI_R), modifiers: optionCommand),
            .speedUp: KeyCombo(keyCode: UInt16(kVK_UpArrow), modifiers: optionCommand),
            .speedDown: KeyCombo(keyCode: UInt16(kVK_DownArrow), modifiers: optionCommand),
            .nextLine: KeyCombo(keyCode: UInt16(kVK_RightArrow), modifiers: optionCommand),
            .previousLine: KeyCombo(keyCode: UInt16(kVK_LeftArrow), modifiers: optionCommand),
            .toggleVoice: KeyCombo(keyCode: UInt16(kVK_ANSI_V), modifiers: optionCommand)
        ]
    }()
}

// MARK: - Store

@MainActor
@Observable
final class ShortcutStore {
    static let shared = ShortcutStore()

    private static let key = "shortcuts"

    private(set) var combos: [ShortcutAction: KeyCombo]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            var restored: [ShortcutAction: KeyCombo] = [:]
            for (raw, combo) in decoded {
                if let action = ShortcutAction(rawValue: raw) { restored[action] = combo }
            }
            combos = restored
        } else {
            combos = ShortcutAction.defaults
        }
    }

    func combo(for action: ShortcutAction) -> KeyCombo? {
        combos[action]
    }

    func set(_ combo: KeyCombo?, for action: ShortcutAction) {
        // A combo can only drive one action at a time.
        if let combo {
            for (other, existing) in combos where other != action && existing == combo {
                combos[other] = nil
            }
        }
        combos[action] = combo
        persist()
        ShortcutsBinder.shared.reload()
    }

    func resetToDefaults() {
        combos = ShortcutAction.defaults
        persist()
        ShortcutsBinder.shared.reload()
    }

    private func persist() {
        var encodable: [String: KeyCombo] = [:]
        for (action, combo) in combos { encodable[action.rawValue] = combo }
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Binder

/// Wires stored combos to the controller's actions.
@MainActor
final class ShortcutsBinder {
    static let shared = ShortcutsBinder()

    private init() {}

    func reload() {
        let manager = HotKeyManager.shared
        manager.unregisterAll()

        for action in ShortcutAction.allCases {
            guard let combo = ShortcutStore.shared.combo(for: action), combo.isValid else { continue }
            manager.register(id: action.hotKeyID, combo: combo) {
                MainActor.assumeIsolated {
                    ShortcutsBinder.shared.perform(action)
                }
            }
        }
    }

    func perform(_ action: ShortcutAction) {
        let controller = PrompterController.shared
        switch action {
        case .togglePlay: controller.togglePlay()
        case .toggleVisible: controller.toggleVisible()
        case .restart: controller.restart()
        case .speedUp: controller.speedUp()
        case .speedDown: controller.speedDown()
        case .nextLine: controller.nextLine()
        case .previousLine: controller.previousLine()
        case .toggleVoice: controller.toggleVoice()
        }
    }
}

// MARK: - Key names

enum KeyCodeNames {
    private static let special: [UInt16: String] = [
        UInt16(kVK_Return): "↩",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "↖",
        UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞",
        UInt16(kVK_PageDown): "⇟",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12"
    ]

    static func name(for keyCode: UInt16) -> String {
        if let special = special[keyCode] { return special }
        if let character = character(for: keyCode) { return character }
        return "Key \(keyCode)"
    }

    /// Ask the current keyboard layout what this physical key prints.
    private static func character(for keyCode: UInt16) -> String? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(-1)
            }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}
