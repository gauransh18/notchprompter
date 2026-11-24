import Foundation
import Observation
import SwiftUI

/// Owns the scroll position of the prompter. Driven once per display refresh by
/// `DisplayLinkView`; everything else just nudges its inputs.
@MainActor
@Observable
final class ScrollEngine {
    var offset: Double = 0
    var isPlaying = false

    var contentHeight: Double = 0
    var viewportHeight: Double = 0
    var lineFrames: [Int: CGRect] = [:]

    /// Set by voice tracking; the engine eases toward it instead of scrolling at a fixed rate.
    var voiceTarget: Double?
    var spokenLine: Int?

    var countdownRemaining: Int = 0
    private var countdownDeadline: Date?

    /// Fires when the position jumps for a reason other than playback (restart, scrub,
    /// nudge, wrap-around), so voice tracking can re-anchor to the new spot.
    @ObservationIgnored var onJump: (() -> Void)?

    var maxOffset: Double { max(0, contentHeight - viewportHeight) }
    var progress: Double { maxOffset > 0 ? min(1, offset / maxOffset) : 0 }
    var isCountingDown: Bool { countdownDeadline != nil }

    // MARK: Transport

    func play(countdown: Int) {
        guard !isPlaying else { return }
        if countdown > 0 {
            countdownRemaining = countdown
            countdownDeadline = Date().addingTimeInterval(TimeInterval(countdown))
        } else {
            isPlaying = true
        }
    }

    func pause() {
        isPlaying = false
        cancelCountdown()
    }

    func toggle(countdown: Int) {
        if isPlaying || isCountingDown {
            pause()
        } else {
            play(countdown: countdown)
        }
    }

    func restart() {
        offset = 0
        voiceTarget = nil
        spokenLine = nil
        cancelCountdown()
        onJump?()
    }

    func nudge(lines: Int, lineHeight: Double) {
        voiceTarget = nil
        offset = (offset + Double(lines) * lineHeight).clamped(to: 0...maxOffset)
        onJump?()
    }

    func scrub(to newOffset: Double) {
        voiceTarget = nil
        offset = newOffset.clamped(to: 0...maxOffset)
        onJump?()
    }

    func scrub(by delta: Double) {
        scrub(to: offset + delta)
    }

    /// The display line sitting at `anchor` (0 = panel top, 1 = panel bottom).
    func line(atAnchor anchor: Double) -> Int? {
        let y = offset + viewportHeight * anchor
        let sorted = lineFrames.sorted { $0.key < $1.key }
        if let hit = sorted.first(where: { $0.value.minY <= y && y < $0.value.maxY }) {
            return hit.key
        }
        // In the gap between two lines, take the next one down.
        return sorted.first(where: { $0.value.minY >= y })?.key ?? sorted.last?.key
    }

    private func cancelCountdown() {
        countdownDeadline = nil
        countdownRemaining = 0
    }

    // MARK: Voice

    /// Park `line` at `anchor` (0 = panel top, 1 = panel bottom) and glide there.
    func follow(line: Int, fraction: Double, anchor: Double) {
        guard let frame = lineFrames[line] else { return }
        spokenLine = line
        let within = frame.height * fraction
        let target = frame.minY + within - viewportHeight * anchor
        voiceTarget = Double(target).clamped(to: 0...maxOffset)
    }

    // MARK: Tick

    func tick(dt: Double, speed: Double, loop: Bool) {
        if let deadline = countdownDeadline {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                cancelCountdown()
                isPlaying = true
            } else {
                countdownRemaining = Int(remaining.rounded(.up))
                return
            }
        }

        if let target = voiceTarget {
            // Critically damped-ish glide: fast enough to keep up, slow enough to read.
            let factor = 1 - pow(0.0001, dt)
            offset += (target - offset) * factor
            if abs(target - offset) < 0.5 { offset = target }
            return
        }

        // The script can shrink under us while it is being edited.
        if contentHeight > 0, offset > maxOffset { offset = maxOffset }

        guard isPlaying else { return }

        offset += speed * dt

        if offset >= maxOffset {
            if loop {
                offset = 0
                onJump?()
            } else {
                offset = maxOffset
                isPlaying = false
            }
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
