import AppKit
import QuartzCore
import SwiftUI

/// Zero-size view that hands the prompter a per-frame tick synced to the display
/// the panel actually lives on.
struct DisplayLinkView: NSViewRepresentable {
    let onTick: (Double) -> Void

    func makeNSView(context: Context) -> DisplayLinkHostView {
        DisplayLinkHostView(onTick: onTick)
    }

    func updateNSView(_ view: DisplayLinkHostView, context: Context) {
        view.onTick = onTick
    }

    static func dismantleNSView(_ view: DisplayLinkHostView, coordinator: ()) {
        view.stop()
    }
}

final class DisplayLinkHostView: NSView {
    var onTick: (Double) -> Void

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    init(onTick: @escaping (Double) -> Void) {
        self.onTick = onTick
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTimestamp = 0
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        // Clamp so a stalled frame (app suspended, display sleep) cannot jump the script.
        let dt = lastTimestamp == 0 ? 1.0 / 60.0 : min(0.1, now - lastTimestamp)
        lastTimestamp = now
        onTick(dt)
    }
}
