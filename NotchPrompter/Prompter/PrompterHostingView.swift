import AppKit
import SwiftUI

/// Hosting view for the prompter panel that turns two-finger trackpad scrolls and
/// mouse-wheel ticks into scrubbing. Scroll events reach the window under the
/// pointer even though the panel never becomes key, so this works while the user
/// is focused on their recording app.
final class PrompterHostingView: NSHostingView<PrompterRootView> {
    /// Positive delta moves further down the script.
    var onScroll: ((Double) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        guard let onScroll else { return super.scrollWheel(with: event) }
        // Trackpads report pixels; a notched mouse wheel reports lines.
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 18
        let delta = -event.scrollingDeltaY * scale
        guard delta != 0 else { return }
        onScroll(Double(delta))
    }
}
