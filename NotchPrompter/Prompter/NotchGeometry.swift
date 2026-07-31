import AppKit

enum NotchGeometry {
    /// The notch cut-out in screen coordinates, or nil on displays without one.
    static func notchRect(on screen: NSScreen) -> CGRect? {
        guard
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea,
            left.width + right.width < screen.frame.width - 1
        else { return nil }

        let width = screen.frame.width - left.width - right.width
        let height = max(left.height, right.height)
        return CGRect(
            x: screen.frame.minX + left.width,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    static func hasNotch(_ screen: NSScreen) -> Bool {
        notchRect(on: screen) != nil
    }

    /// Height of the menu bar strip, used as the minimum panel height so the
    /// prompter always fully covers the notch row.
    static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        if let notch = notchRect(on: screen) { return notch.height }
        return max(24, screen.frame.maxY - screen.visibleFrame.maxY)
    }
}
