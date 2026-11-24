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

    /// Short-lived message shown inside the panel, e.g. after a speed hotkey.
    private(set) var hud: HUDMessage?

    struct HUDMessage: Equatable {
        let id = UUID()
        let symbol: String
        let text: String
    }

    @ObservationIgnored private var panel: PrompterPanel?
    @ObservationIgnored private var voice: VoiceTracker?
    @ObservationIgnored private var moveObserver: NSObjectProtocol?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var scriptDebounce: Task<Void, Never>?
    @ObservationIgnored private var hudDismiss: Task<Void, Never>?

    private static let visibilityKey = "prompterVisible"

    private init() {
        model = ScriptModel(script: AppSettings.shared.script)
        engine.onJump = { [weak self] in self?.resyncVoiceToScroll() }
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
        let hosting = PrompterHostingView(rootView: PrompterRootView(controller: self))
        hosting.onScroll = { [weak self] delta in
            self?.engine.scrub(by: delta)
        }
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

        // Plugging in or unplugging a display, or changing its resolution, moves
        // the notch out from under us.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyLayout()
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
        isVisible = true
        // If it is still fading out, just reverse the fade from where it is.
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        UserDefaults.standard.set(true, forKey: Self.visibilityKey)

        if settings.autoStart { engine.play(countdown: settings.countdown) }
        syncVoice()
    }

    func hide() {
        if let panel {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    // Shown again before the fade finished: leave it up.
                    guard let self, !self.isVisible else { return }
                    panel.orderOut(nil)
                }
            })
        }
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
        settings.scrollSpeed = min(AppSettings.speedRange.upperBound, settings.scrollSpeed + 4)
        flashSpeed(symbol: "hare")
    }

    func speedDown() {
        settings.scrollSpeed = max(AppSettings.speedRange.lowerBound, settings.scrollSpeed - 4)
        flashSpeed(symbol: "tortoise")
    }

    private func flashSpeed(symbol: String) {
        flash(symbol: symbol, "\(Int(settings.scrollSpeed)) px/s")
    }

    /// Show a brief confirmation inside the panel. Hotkeys fire while the user is in
    /// another app, so this is the only feedback they get.
    func flash(symbol: String, _ text: String) {
        guard isVisible else { return }
        let message = HUDMessage(symbol: symbol, text: text)
        hud = message
        hudDismiss?.cancel()
        hudDismiss = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled, let self, self.hud == message else { return }
            self.hud = nil
        }
    }

    func nextLine() {
        engine.nudge(lines: 1, lineHeight: lineHeight)
    }

    func previousLine() {
        engine.nudge(lines: -1, lineHeight: lineHeight)
    }

    func toggleVoice() {
        settings.voiceEnabled.toggle()
        flash(symbol: settings.voiceEnabled ? "waveform" : "waveform.slash",
              settings.voiceEnabled ? "Voice follow on" : "Voice follow off")
    }

    private var lineHeight: Double {
        settings.fontSize * 1.25 + settings.lineSpacing
    }

    // MARK: Layout

    func applyLayout() {
        guard let panel, var screen = settings.targetScreen else { return }
        let width = max(120, settings.panelWidth)
        let height = max(40, settings.panelHeight)

        // A custom position belongs to whichever display it was dropped on.
        if settings.position == .custom, settings.customX != 0 || settings.customY != 0 {
            let center = CGPoint(x: settings.customX + width / 2, y: settings.customY + height / 2)
            if let home = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
                screen = home
            }
        }

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
        resyncVoiceToScroll()
    }

    /// After a jump the speaker starts reading from what is on screen, so point the
    /// matcher at the top visible line. Its look-ahead covers the rest of the panel.
    private func resyncVoiceToScroll() {
        guard let voice, voice.isActive else { return }
        let line = engine.offset <= 0.5 ? 0 : (engine.line(atAnchor: 0) ?? 0)
        voice.seek(toToken: model.firstToken(atOrAfterLine: line))
    }

    private func stopVoice() {
        voice?.stop()
        engine.voiceTarget = nil
        engine.spokenLine = nil
        if voiceStatus != .idle { voiceStatus = .idle }
    }

    // MARK: Observation

    /// Typing in the editor fires this on every keystroke. Rebuilding the model and
    /// re-seeding voice tracking is debounced, the scroll position is kept, and the
    /// microphone is never torn down for an edit.
    private func trackScript() {
        track({ _ = self.settings.script }) { [weak self] in
            guard let self else { return }
            self.scriptDebounce?.cancel()
            self.scriptDebounce = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, let self else { return }
                self.applyScript()
            }
        }
    }

    private func applyScript() {
        model = ScriptModel(script: settings.script)
        if let spoken = engine.spokenLine, spoken >= model.lines.count {
            engine.spokenLine = nil
        }
        engine.voiceTarget = nil
        if let voice, voice.isActive {
            voice.update(model: model, lookahead: settings.voiceLookahead)
        } else if settings.voiceEnabled && isVisible {
            startVoice()
        }
    }

    /// Jump back to the top after the whole script was replaced (import, sample, clear).
    func scriptReplaced() {
        scriptDebounce?.cancel()
        applyScript()
        engine.restart()
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
        track({ _ = self.settings.voiceLookahead }) { [weak self] in
            guard let self, let voice = self.voice, voice.isActive else { return }
            voice.update(model: self.model, lookahead: self.settings.voiceLookahead)
        }
    }

    /// Re-arming observation: `withObservationTracking` fires once, so we resubscribe
    /// after each change. The callback runs on the next main-actor hop, by which point
    /// the new value is committed.
    private func track(_ read: @escaping () -> Void, onChange: @escaping () -> Void) {
        withObservationTracking {
            read()
        } onChange: { [weak self] in
            Task { @MainActor in
                onChange()
                self?.track(read, onChange: onChange)
            }
        }
    }
}
