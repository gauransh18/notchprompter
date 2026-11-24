import AVFoundation
import Foundation
import Speech

/// Streams the microphone into on-device speech recognition and reports which
/// script token the speaker has reached.
///
/// The audio tap is installed once and left alone. Only the recognition request is
/// cycled, because `SFSpeechRecognitionTask` gives up after about a minute of audio
/// and tearing the engine down on that schedule is what makes AVAudioEngine throw.
@MainActor
final class VoiceTracker {
    enum Status: Equatable {
        case idle
        case requestingPermission
        case listening
        case denied
        case unavailable(String)

        var label: String {
            switch self {
            case .idle: return "Not listening"
            case .requestingPermission: return "Waiting for permission…"
            case .listening: return "Listening"
            case .denied: return "Permission denied"
            case .unavailable(let reason): return reason
            }
        }
    }

    var onMatch: ((Int) -> Void)?
    var onStatusChange: ((Status) -> Void)?

    private(set) var status: Status = .idle {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }

    private let audioEngine = AVAudioEngine()
    private let requestBox = RequestBox()

    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var matcher: ScriptMatcher?

    private var localeIdentifier = Locale.current.identifier
    private var onDeviceOnly = true
    private var isRunning = false
    private var isTapInstalled = false
    private var rotateTimer: Timer?

    /// Recognition tasks are capped at roughly a minute of audio, so cycle earlier.
    private let rotateInterval: TimeInterval = 45
    private var sessionStartedAt = Date.distantPast
    private var consecutiveFailures = 0

    /// Bumped whenever a recognition task is torn down. A cancelled task still calls
    /// its result handler, so every callback carries the generation it was born in
    /// and anything stale is dropped instead of being charged to the next session.
    private var generation = 0
    private var pendingRestart: DispatchWorkItem?

    /// Words of the current transcript to ignore after a seek, so what was said before
    /// the jump cannot drag the cursor back to where it was.
    private var ignoredWordCount = 0
    private var lastWordCount = 0

    // MARK: Control

    func start(model: ScriptModel, localeIdentifier: String, onDeviceOnly: Bool, lookahead: Int) {
        stop()

        guard !model.tokens.isEmpty else {
            status = .unavailable("Script has no spoken words")
            return
        }

        matcher = ScriptMatcher(tokens: model.tokens, lookahead: lookahead)
        self.localeIdentifier = localeIdentifier
        self.onDeviceOnly = onDeviceOnly
        isRunning = true
        consecutiveFailures = 0
        status = .requestingPermission

        requestPermissions { [weak self] granted in
            guard let self, self.isRunning else { return }
            guard granted else {
                self.status = .denied
                self.isRunning = false
                return
            }
            guard self.startAudio() else { return }
            self.startRecognition()
        }
    }

    func stop() {
        isRunning = false
        rotateTimer?.invalidate()
        rotateTimer = nil
        endRecognition()
        stopAudio()
        matcher = nil
        status = .idle
    }

    var isActive: Bool { isRunning }

    /// Swap in a new script without touching the microphone or the recognition task.
    func update(model: ScriptModel, lookahead: Int) {
        guard isRunning else { return }
        let cursor = matcher?.cursor ?? 0
        var next = ScriptMatcher(tokens: model.tokens, lookahead: lookahead)
        next.seek(to: cursor)
        matcher = next
    }

    /// Tell the matcher where the speaker is now, after a scrub, nudge or restart.
    func seek(toToken token: Int) {
        guard isRunning, matcher != nil else { return }
        matcher?.seek(to: token)
        ignoredWordCount = lastWordCount
    }

    // MARK: Permissions

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { micGranted in
            guard micGranted else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            SFSpeechRecognizer.requestAuthorization { authStatus in
                DispatchQueue.main.async { completion(authStatus == .authorized) }
            }
        }
    }

    static var speechAuthorization: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    static var microphoneAuthorization: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    // MARK: Audio

    /// Installs the tap and starts the engine. Returns false (and sets a status) on failure.
    private func startAudio() -> Bool {
        guard !isTapInstalled else { return true }

        let input = audioEngine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            fail("No audio input device")
            return false
        }

        let box = requestBox
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            box.append(buffer)
        }
        isTapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stopAudio()
            fail("Microphone failed: \(error.localizedDescription)")
            return false
        }
        return true
    }

    private func stopAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        audioEngine.reset()
    }

    // MARK: Recognition

    private func startRecognition() {
        guard isRunning else { return }

        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
            fail("No recogniser for \(locale.identifier)")
            return
        }
        guard recognizer.isAvailable else {
            fail("Recogniser unavailable right now")
            return
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if onDeviceOnly && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        requestBox.set(request)

        sessionStartedAt = Date()
        ignoredWordCount = 0
        lastWordCount = 0
        let born = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let finished = (result?.isFinal ?? false) || error != nil
            DispatchQueue.main.async {
                guard let self, born == self.generation else { return }
                if let transcript { self.handle(transcript: transcript) }
                if finished { self.rotate(afterError: error != nil) }
            }
        }

        status = .listening
        scheduleRotation()
    }

    private func endRecognition() {
        generation += 1
        pendingRestart?.cancel()
        pendingRestart = nil
        task?.cancel()
        task = nil
        requestBox.finish()
    }

    private func scheduleRotation() {
        rotateTimer?.invalidate()
        rotateTimer = Timer.scheduledTimer(withTimeInterval: rotateInterval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.rotate(afterError: false) }
        }
    }

    /// Swap in a fresh recognition request without touching the audio graph.
    private func rotate(afterError: Bool) {
        guard isRunning else { return }

        if afterError && Date().timeIntervalSince(sessionStartedAt) < 2 {
            consecutiveFailures += 1
            if consecutiveFailures >= 3 {
                let reason = "Speech recognition keeps failing — check the language model"
                stop()
                status = .unavailable(reason)
                return
            }
        } else {
            consecutiveFailures = 0
        }

        rotateTimer?.invalidate()
        rotateTimer = nil
        endRecognition()

        // Small gap so the previous task fully unwinds before the next one starts.
        let restart = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            self.pendingRestart = nil
            self.startRecognition()
        }
        pendingRestart = restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: restart)
    }

    private func fail(_ reason: String) {
        isRunning = false
        endRecognition()
        stopAudio()
        status = .unavailable(reason)
    }

    // MARK: Matching

    private func handle(transcript: String) {
        guard isRunning, var matcher else { return }
        let words = ScriptModel.tokenize(transcript)
        lastWordCount = words.count
        // Partial results can revise themselves shorter; never ignore more than we have.
        ignoredWordCount = min(ignoredWordCount, words.count)
        let spoken = Array(words.dropFirst(ignoredWordCount))
        guard !spoken.isEmpty else { return }
        if let matched = matcher.consume(spoken: spoken) {
            onMatch?(matched)
        }
        self.matcher = matcher
    }
}

/// The audio tap runs on a realtime thread while the main actor swaps requests,
/// so the handoff needs its own lock.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ newRequest: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        let previous = request
        request = newRequest
        lock.unlock()
        previous?.endAudio()
    }

    func finish() {
        set(nil)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = request
        lock.unlock()
        current?.append(buffer)
    }
}
