import AppKit
import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                NSLog("NotchPrompter: login item update failed — \(error.localizedDescription)")
            }
        }
    }

    /// True when launchd started us as a login item rather than the user opening the app.
    /// Only meaningful while the launch Apple event is still current, i.e. during
    /// `applicationWillFinishLaunching` / `applicationDidFinishLaunching`.
    static var wasLaunchedByLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        guard event.eventID == kAEOpenApplication else { return false }
        let property = event.paramDescriptor(forKeyword: keyAEPropData)
        return property?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
