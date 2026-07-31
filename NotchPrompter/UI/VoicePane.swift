import AppKit
import AVFoundation
import Speech
import SwiftUI

struct VoicePane: View {
    @Bindable var settings: AppSettings
    var controller: PrompterController

    var body: some View {
        Form {
            Section {
                Toggle("Follow my voice", isOn: $settings.voiceEnabled)
                Text("The script scrolls itself to wherever you are in the text, so a pause or an ad-lib never leaves you behind.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Recognition") {
                Picker("Language", selection: $settings.voiceLocale) {
                    ForEach(Self.locales, id: \.identifier) { locale in
                        Text(label(for: locale)).tag(locale.identifier)
                    }
                }

                Toggle("Keep recognition on this Mac", isOn: $settings.voiceOnDeviceOnly)
                Text("On-device recognition never sends audio to Apple. Turn it off only if your language has no offline model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tracking") {
                SliderRow(
                    title: "Look ahead",
                    value: Binding(
                        get: { Double(settings.voiceLookahead) },
                        set: { settings.voiceLookahead = Int($0) }
                    ),
                    range: 10...120,
                    step: 5
                ) { "\(Int($0)) words" }

                Text("How far ahead the matcher will jump when you skip a chunk. Lower is steadier, higher recovers faster.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SliderRow(title: "Reading line", value: $settings.voiceAnchor, range: 0.1...0.8, step: 0.05) {
                    "\(Int($0 * 100))% down"
                }
            }

            Section("Status") {
                LabeledContent("Voice tracking") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        Text(controller.voiceStatus.label)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Microphone") {
                    Text(micLabel).foregroundStyle(.secondary)
                }

                LabeledContent("Speech recognition") {
                    Text(speechLabel).foregroundStyle(.secondary)
                }

                if needsSystemSettings {
                    Button("Open Privacy Settings…") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var statusColor: Color {
        switch controller.voiceStatus {
        case .listening: return .green
        case .requestingPermission: return .orange
        case .denied, .unavailable: return .red
        case .idle: return .secondary
        }
    }

    private var micLabel: String {
        switch VoiceTracker.microphoneAuthorization {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    private var speechLabel: String {
        switch VoiceTracker.speechAuthorization {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    private var needsSystemSettings: Bool {
        VoiceTracker.microphoneAuthorization == .denied || VoiceTracker.speechAuthorization == .denied
    }

    private func label(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    private static let locales: [Locale] = {
        SFSpeechRecognizer.supportedLocales()
            .sorted {
                let left = Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier
                let right = Locale.current.localizedString(forIdentifier: $1.identifier) ?? $1.identifier
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
    }()
}
