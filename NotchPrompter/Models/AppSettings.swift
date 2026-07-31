import AppKit
import SwiftUI
import Observation

// MARK: - Enums

enum FontStyle: String, CaseIterable, Identifiable {
    case standard, serif, rounded, mono, dyslexic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Default"
        case .serif: return "Serif"
        case .rounded: return "Round"
        case .mono: return "Mono"
        case .dyslexic: return "Dyslexic"
        }
    }

    var design: Font.Design {
        switch self {
        case .standard: return .default
        case .serif: return .serif
        case .rounded: return .rounded
        case .mono: return .monospaced
        case .dyslexic: return .rounded
        }
    }

    /// Extra letter spacing. The dyslexia-friendly preset widens tracking, which is
    /// the part of OpenDyslexic-style typography we can reproduce without bundling a font.
    var tracking: CGFloat {
        self == .dyslexic ? 1.4 : 0
    }

    var weight: Font.Weight {
        self == .dyslexic ? .semibold : .regular
    }
}

enum TextAlign: String, CaseIterable, Identifiable {
    case leading, center, trailing

    var id: String { rawValue }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var symbol: String {
        switch self {
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }
}

enum PanelPosition: String, CaseIterable, Identifiable {
    case left, center, right, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        case .custom: return "Custom"
        }
    }

    var symbol: String {
        switch self {
        case .left: return "inset.filled.leadinghalf.arrow.leading.rectangle"
        case .center: return "inset.filled.center.rectangle"
        case .right: return "inset.filled.trailinghalf.arrow.trailing.rectangle"
        case .custom: return "hand.draw"
        }
    }
}

// MARK: - Store

/// Every user-facing preference lives here. Values write straight back to
/// `UserDefaults` on `didSet`, so nothing needs an explicit save step.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let store = UserDefaults.standard

    // Script
    var script: String { didSet { store.set(script, forKey: K.script) } }

    // Appearance
    var fontStyle: FontStyle { didSet { store.set(fontStyle.rawValue, forKey: K.fontStyle) } }
    var fontSize: Double { didSet { store.set(fontSize, forKey: K.fontSize) } }
    var lineSpacing: Double { didSet { store.set(lineSpacing, forKey: K.lineSpacing) } }
    var alignment: TextAlign { didSet { store.set(alignment.rawValue, forKey: K.alignment) } }

    // Prompter window
    var panelWidth: Double { didSet { store.set(panelWidth, forKey: K.panelWidth) } }
    var panelHeight: Double { didSet { store.set(panelHeight, forKey: K.panelHeight) } }
    var position: PanelPosition { didSet { store.set(position.rawValue, forKey: K.position) } }
    var customX: Double { didSet { store.set(customX, forKey: K.customX) } }
    var customY: Double { didSet { store.set(customY, forKey: K.customY) } }
    var screenID: String { didSet { store.set(screenID, forKey: K.screenID) } }
    var verticalOffset: Double { didSet { store.set(verticalOffset, forKey: K.verticalOffset) } }

    // Visuals
    var backgroundOpacity: Double { didSet { store.set(backgroundOpacity, forKey: K.backgroundOpacity) } }
    var cornerRadius: Double { didSet { store.set(cornerRadius, forKey: K.cornerRadius) } }
    var textColorHex: String { didSet { store.set(textColorHex, forKey: K.textColorHex) } }
    var backgroundColorHex: String { didSet { store.set(backgroundColorHex, forKey: K.backgroundColorHex) } }
    var highlightColorHex: String { didSet { store.set(highlightColorHex, forKey: K.highlightColorHex) } }
    var fadeEdges: Bool { didSet { store.set(fadeEdges, forKey: K.fadeEdges) } }
    var dimUnreadLines: Bool { didSet { store.set(dimUnreadLines, forKey: K.dimUnreadLines) } }
    var mirrorText: Bool { didSet { store.set(mirrorText, forKey: K.mirrorText) } }

    // Behavior
    var scrollSpeed: Double { didSet { store.set(scrollSpeed, forKey: K.scrollSpeed) } }
    var autoStart: Bool { didSet { store.set(autoStart, forKey: K.autoStart) } }
    var countdown: Int { didSet { store.set(countdown, forKey: K.countdown) } }
    var loopScript: Bool { didSet { store.set(loopScript, forKey: K.loopScript) } }
    var clickThrough: Bool { didSet { store.set(clickThrough, forKey: K.clickThrough) } }
    var hideFromCapture: Bool { didSet { store.set(hideFromCapture, forKey: K.hideFromCapture) } }
    var showOverFullscreen: Bool { didSet { store.set(showOverFullscreen, forKey: K.showOverFullscreen) } }
    var resetOnHide: Bool { didSet { store.set(resetOnHide, forKey: K.resetOnHide) } }
    var launchAtLogin: Bool { didSet { LaunchAtLogin.isEnabled = launchAtLogin } }

    // Voice
    var voiceEnabled: Bool { didSet { store.set(voiceEnabled, forKey: K.voiceEnabled) } }
    var voiceLocale: String { didSet { store.set(voiceLocale, forKey: K.voiceLocale) } }
    var voiceOnDeviceOnly: Bool { didSet { store.set(voiceOnDeviceOnly, forKey: K.voiceOnDeviceOnly) } }
    /// How many tokens ahead of the cursor the matcher is allowed to jump.
    var voiceLookahead: Int { didSet { store.set(voiceLookahead, forKey: K.voiceLookahead) } }
    /// Where in the panel the spoken line is parked (0 = top edge, 1 = bottom edge).
    var voiceAnchor: Double { didSet { store.set(voiceAnchor, forKey: K.voiceAnchor) } }

    private init() {
        script = store.string(K.script, AppSettings.sampleScript)

        fontStyle = FontStyle(rawValue: store.string(K.fontStyle, "")) ?? .mono
        fontSize = store.double(K.fontSize, 15)
        lineSpacing = store.double(K.lineSpacing, 2)
        alignment = TextAlign(rawValue: store.string(K.alignment, "")) ?? .leading

        panelWidth = store.double(K.panelWidth, 470)
        panelHeight = store.double(K.panelHeight, 145)
        position = PanelPosition(rawValue: store.string(K.position, "")) ?? .center
        customX = store.double(K.customX, 0)
        customY = store.double(K.customY, 0)
        screenID = store.string(K.screenID, "")
        verticalOffset = store.double(K.verticalOffset, 0)

        backgroundOpacity = store.double(K.backgroundOpacity, 1)
        cornerRadius = store.double(K.cornerRadius, 14)
        textColorHex = store.string(K.textColorHex, "FFFFFF")
        backgroundColorHex = store.string(K.backgroundColorHex, "000000")
        highlightColorHex = store.string(K.highlightColorHex, "FFD60A")
        fadeEdges = store.bool(K.fadeEdges, true)
        dimUnreadLines = store.bool(K.dimUnreadLines, false)
        mirrorText = store.bool(K.mirrorText, false)

        scrollSpeed = store.double(K.scrollSpeed, 22)
        autoStart = store.bool(K.autoStart, false)
        countdown = store.int(K.countdown, 3)
        loopScript = store.bool(K.loopScript, false)
        clickThrough = store.bool(K.clickThrough, false)
        hideFromCapture = store.bool(K.hideFromCapture, false)
        showOverFullscreen = store.bool(K.showOverFullscreen, true)
        resetOnHide = store.bool(K.resetOnHide, false)
        launchAtLogin = LaunchAtLogin.isEnabled

        voiceEnabled = store.bool(K.voiceEnabled, false)
        voiceLocale = store.string(K.voiceLocale, Locale.current.identifier)
        voiceOnDeviceOnly = store.bool(K.voiceOnDeviceOnly, true)
        voiceLookahead = store.int(K.voiceLookahead, 40)
        voiceAnchor = store.double(K.voiceAnchor, 0.35)
    }

    // MARK: Derived

    var textColor: Color { Color(hex: textColorHex) }
    var backgroundColor: Color { Color(hex: backgroundColorHex) }
    var highlightColor: Color { Color(hex: highlightColorHex) }

    var font: Font {
        .system(size: fontSize, weight: fontStyle.weight, design: fontStyle.design)
    }

    var wordCount: Int {
        script.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Rough read time at a conversational 150 words per minute.
    var estimatedDuration: TimeInterval {
        Double(wordCount) / 150.0 * 60.0
    }

    /// Nil only when the Mac has no active display, e.g. clamshell with nothing attached.
    var targetScreen: NSScreen? {
        if let match = NSScreen.screens.first(where: { $0.persistentIdentifier == screenID }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    func resetAppearance() {
        fontStyle = .mono
        fontSize = 15
        lineSpacing = 2
        alignment = .leading
        panelWidth = 470
        panelHeight = 145
        position = .center
        verticalOffset = 0
        backgroundOpacity = 1
        cornerRadius = 14
        textColorHex = "FFFFFF"
        backgroundColorHex = "000000"
        highlightColorHex = "FFD60A"
        fadeEdges = true
        dimUnreadLines = false
        mirrorText = false
    }

    static let sampleScript = """
    [Intro Music — Upbeat & Snappy]

    Stop looking at your keyboard and start looking at your audience.

    [Pause]

    This is NotchPrompter. It's a tiny Mac app that hides your script right inside your camera notch. See the difference?

    [Pause]

    No more "shifty eyes," no more taped-up sticky notes — just perfect eye contact, every time you record.
    """
}

// MARK: - Keys

private enum K {
    static let script = "script"
    static let fontStyle = "fontStyle"
    static let fontSize = "fontSize"
    static let lineSpacing = "lineSpacing"
    static let alignment = "alignment"
    static let panelWidth = "panelWidth"
    static let panelHeight = "panelHeight"
    static let position = "position"
    static let customX = "customX"
    static let customY = "customY"
    static let screenID = "screenID"
    static let verticalOffset = "verticalOffset"
    static let backgroundOpacity = "backgroundOpacity"
    static let cornerRadius = "cornerRadius"
    static let textColorHex = "textColorHex"
    static let backgroundColorHex = "backgroundColorHex"
    static let highlightColorHex = "highlightColorHex"
    static let fadeEdges = "fadeEdges"
    static let dimUnreadLines = "dimUnreadLines"
    static let mirrorText = "mirrorText"
    static let scrollSpeed = "scrollSpeed"
    static let autoStart = "autoStart"
    static let countdown = "countdown"
    static let loopScript = "loopScript"
    static let clickThrough = "clickThrough"
    static let hideFromCapture = "hideFromCapture"
    static let showOverFullscreen = "showOverFullscreen"
    static let resetOnHide = "resetOnHide"
    static let voiceEnabled = "voiceEnabled"
    static let voiceLocale = "voiceLocale"
    static let voiceOnDeviceOnly = "voiceOnDeviceOnly"
    static let voiceLookahead = "voiceLookahead"
    static let voiceAnchor = "voiceAnchor"
}

// MARK: - Defaults helpers

private extension UserDefaults {
    func double(_ key: String, _ fallback: Double) -> Double {
        object(forKey: key) == nil ? fallback : double(forKey: key)
    }

    func bool(_ key: String, _ fallback: Bool) -> Bool {
        object(forKey: key) == nil ? fallback : bool(forKey: key)
    }

    func int(_ key: String, _ fallback: Int) -> Int {
        object(forKey: key) == nil ? fallback : integer(forKey: key)
    }

    func string(_ key: String, _ fallback: String) -> String {
        string(forKey: key) ?? fallback
    }
}

extension NSScreen {
    /// Stable-per-boot identifier so the chosen display survives relaunches.
    var persistentIdentifier: String {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return "\(number?.uint32Value ?? 0)"
    }
}
