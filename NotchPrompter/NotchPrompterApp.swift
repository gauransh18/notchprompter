import AppKit
import SwiftUI

@main
struct NotchPrompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private var controller = PrompterController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(controller: controller, settings: controller.settings)
        } label: {
            Image(systemName: controller.isVisible ? "captions.bubble.fill" : "captions.bubble")
        }
        .commands {
            // Without these the script editor would have no ⌘C / ⌘V / ⌘Z,
            // since a menu-bar-only app gets no Edit menu by default.
            TextEditingCommands()

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    SettingsWindowController.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

// MARK: - Menu

struct MenuBarContent: View {
    var controller: PrompterController
    @Bindable var settings: AppSettings

    var body: some View {
        Button(controller.isVisible ? "Hide Prompter" : "Show Prompter") {
            controller.toggleVisible()
        }
        .keyboardShortcut("n", modifiers: [.command, .option])

        Button(controller.engine.isPlaying ? "Pause Scrolling" : "Start Scrolling") {
            controller.togglePlay()
        }

        Button("Back to Start") {
            controller.restart()
        }

        Divider()

        Toggle("Follow My Voice", isOn: $settings.voiceEnabled)

        Menu("Speed") {
            Button("Faster") { controller.speedUp() }
            Button("Slower") { controller.speedDown() }
            Divider()
            Text("\(Int(settings.scrollSpeed)) px/s")
        }

        Divider()

        Button("Settings…") {
            SettingsWindowController.shared.show()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit NotchPrompter") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

// MARK: - Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.accessory)
            ShortcutsBinder.shared.reload()
            PrompterController.shared.restoreVisibility()

            // Opening the app by hand should show its window; a login-item launch should not.
            if !LaunchAtLogin.wasLaunchedByLoginItem {
                SettingsWindowController.shared.show()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            SettingsWindowController.shared.show()
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
