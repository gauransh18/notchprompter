import SwiftUI

struct BehaviorPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Scrolling") {
                SliderRow(title: "Scroll speed", value: $settings.scrollSpeed, range: 2...160) {
                    "\(Int($0)) px/s"
                }

                Toggle("Start scrolling as soon as the prompter appears", isOn: $settings.autoStart)

                Picker("Countdown before scrolling", selection: $settings.countdown) {
                    Text("Off").tag(0)
                    ForEach([1, 2, 3, 5, 10], id: \.self) { seconds in
                        Text("\(seconds)s").tag(seconds)
                    }
                }

                Toggle("Loop back to the top at the end", isOn: $settings.loopScript)
                Toggle("Jump back to the top when hidden", isOn: $settings.resetOnHide)
            }

            Section("Prompter Window") {
                Toggle("Click through the prompter", isOn: $settings.clickThrough)
                Text("Clicks and scrolls pass to whatever is behind the prompter. Turn this off to drag or scrub it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Hide from screen recording and screen sharing", isOn: $settings.hideFromCapture)
                Text("Your script stays off the recording, so viewers never see it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Stay visible over full-screen apps", isOn: $settings.showOverFullscreen)
            }

            Section("System") {
                Toggle("Launch NotchPrompter at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }
}
