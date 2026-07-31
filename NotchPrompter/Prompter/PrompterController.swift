import AppKit
import Observation
import SwiftUI

/// Owns the floating panel and every action that can be triggered from the menu
/// bar, the settings window or a global hotkey.
@MainActor
@Observable
final class PrompterController {
    static let shared = PrompterController()

    let settings = AppSettings.shared
    let engine = ScrollEngine()
    private(set) var model: ScriptModel

    var isVisible = false
    var voiceStatus: VoiceTracker.Status = .idle

    @ObservationIgnored private var panel: PrompterPanel?
    @ObservationIgnored private var voice: VoiceTracker?
    @ObservationIgnored private var moveObserver: NSObjectProtocol?

    private static let visibilityKey = "prompterVisible"

    private init() {
        model = ScriptModel(script: AppSettings.shared.script)
        trackScript()
        trackLayout()
        trackBehavior()
        trackVoicePreference()
    }

    // MARK: Lifecycle

    func restoreVisibility() {
        if UserDefaults.standard.bool(forKey: Self.visibilityKey) {
            show()
        }
    }

    private func ensurePanel() -> PrompterPanel {
        if let panel { return panel }

        let panel = PrompterPanel(contentRect: NSRect(x: 0, y: 0, width: settings.panelWidth, height: settings.panelHeight))
        let hosting = NSHostingView(rootView: PrompterRootView(controller: self))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        self.panel = panel

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.persistCustomPosition()
            }
        }

        applyLayout()
        applyBehavior()
        return panel
    }

    // MARK: Visibility

    func show() {
        let panel = ensurePanel()
        applyLayout()
        applyBehavior()
        panel.orderFrontRegardless()
        isVisible = true
        UserDefaults.standard.set(true, forKey: Self.visibilityKey)

        if settings.autoStart { engine.play(countdown: settings.countdown) }
        syncVoice()
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        UserDefaults.standard.set(false, forKey: Self.visibilityKey)
        engine.pause()
        if settings.resetOnHide { engine.restart() }
        stopVoice()
    }

    func toggleVisible() {
        isVisible ? hide() : show()
    }

    // MARK: Transport

    func togglePlay() {
        if !isVisible { show() }
        engine.toggle(countdown: settings.countdown)
    }

    func restart() {
        engine.restart()
    }

    func speedUp() {
        settings.scrollSpeed = min(200, settings.scrollSpeed + 4)
    }

    func speedDown() {
        settings.scrollSpeed = max(2, settings.scrollSpeed - 4)
    }

    func nextLine() {
        engine.nudge(lines: 1, lineHeight: lineHeight)
    }

    func previousLine() {
        engine.nudge(lines: -1, lineHeight: lineHeight)
    }

    func toggleVoice() {
        settings.voiceEnabled.toggle()
    }

    private var lineHeight: Double {
        settings.fontSize * 1.25 + settings.lineSpacing
    }

    // MARK: Layout

    func applyLayout() {
        guard let panel, let screen = settings.targetScreen else { return }
        let width = max(120, settings.panelWidth)
        let height = max(40, settings.panelHeight)

        var origin: CGPoint
        switch settings.position {
        case .left:
            origin = CGPoint(x: screen.frame.minX + 12, y: screen.frame.maxY - height - settings.verticalOffset)
        case .center:
            origin = CGPoint(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height - settings.verticalOffset)
        case .right:
            origin = CGPoint(x: screen.frame.maxX - width - 12, y: screen.frame.maxY - height - settings.verticalOffset)
        case .custom:
            if settings.customX == 0 && settings.customY == 0 {
                origin = CGPoint(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height)
            } else {
                origin = CGPoint(x: settings.customX, y: settings.customY)
            }
        }

        // Keep at least a sliver on-screen if the display layout changed under us.
        let bounds = screen.frame
        origin.x = origin.x.clamped(to: (bounds.minX - width + 60)...(bounds.maxX - 60))
        origin.y = origin.y.clamped(to: (bounds.minY - height + 40)...(bounds.maxY - height))

        panel.setFrame(NSRect(origin: origin, size: CGSize(width: width, height: height)), display: true)
    }

    func applyBehavior() {
        guard let panel else { return }
        panel.ignoresMouseEvents = settings.clickThrough
        // `.none` keeps the panel out of screen recordings and shared screens.
        panel.sharingType = settings.hideFromCapture ? .none : .readOnly
        panel.level = settings.showOverFullscreen ? .screenSaver : .statusBar
        panel.isMovableByWindowBackground = settings.position == .custom && !settings.clickThrough
    }

    private func persistCustomPosition() {
        guard let panel, settings.position == .custom else { return }
        settings.customX = Double(panel.frame.origin.x)
        settings.customY = Double(panel.frame.origin.y)
    }

    // MARK: Voice

    private func syncVoice() {
        if settings.voiceEnabled && isVisible {
            startVoice()
        } else {
            stopVoice()
        }
    }

    private func startVoice() {
        if voice == nil {
            voice = VoiceTracker()
        }
        voice?.onStatusChange = { [weak self] status in
            self?.voiceStatus = status
        }
        voice?.onMatch = { [weak self] tokenIndex in
            guard let self else { return }
            guard let line = self.model.lineIndex(forToken: tokenIndex) else { return }
            let fraction = self.model.fraction(ofToken: tokenIndex)
            self.engine.follow(line: line, fraction: fraction, anchor: self.settings.voiceAnchor)
        }
        voice?.start(model: model, localeIdentifier: settings.voiceLocale, onDeviceOnly: settings.voiceOnDeviceOnly, lookahead: settings.voiceLookahead)
    }

    private func stopVoice() {
        voice?.stop()
        engine.voiceTarget = nil
        engine.spokenLine = nil
        if voiceStatus != .idle { voiceStatus = .idle }
    }

    // MARK: Observation

    private func trackScript() {
        track({ _ = self.settings.script }) { [weak self] in
            guard let self else { return }
            self.model = ScriptModel(script: self.settings.script)
            self.engine.restart()
            if self.settings.voiceEnabled && self.isVisible { self.startVoice() }
        }
    }

    private func trackLayout() {
        track({
            _ = self.settings.panelWidth
            _ = self.settings.panelHeight
            _ = self.settings.position
            _ = self.settings.verticalOffset
            _ = self.settings.screenID
        }) { [weak self] in
            self?.applyLayout()
            self?.applyBehavior()
        }
    }

    private func trackBehavior() {
        track({
            _ = self.settings.clickThrough
            _ = self.settings.hideFromCapture
            _ = self.settings.showOverFullscreen
        }) { [weak self] in
            self?.applyBehavior()
        }
    }

    private func trackVoicePreference() {
        track({
            _ = self.settings.voiceEnabled
            _ = self.settings.voiceLocale
            _ = self.settings.voiceOnDeviceOnly
        }) { [weak self] in
            self?.syncVoice()
        }
    }

    /// Re-arming observation: `withObservationTracking` fires once, so we resubscribe
    /// after each change. The callback runs on the next main-actor hop, by which point
    /// the new value is committed.
    private func track(_ read: @escaping () -> Void, onChange: @escaping () -> Void) {
        withObservationTracking {
            read()
        } onChange: {
            Task { @MainActor [weak self] in
                onChange()
                self?.track(read, onChange: onChange)
            }
        }
    }
}
