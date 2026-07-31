import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case script, appearance, behavior, voice, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .script: return "Script"
        case .appearance: return "Appearance"
        case .behavior: return "Behavior"
        case .voice: return "Voice"
        case .shortcuts: return "Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .script: return "text.alignleft"
        case .appearance: return "paintbrush"
        case .behavior: return "slider.horizontal.3"
        case .voice: return "waveform"
        case .shortcuts: return "keyboard"
        }
    }
}

struct SettingsWindowView: View {
    @Bindable var settings = AppSettings.shared
    var controller = PrompterController.shared

    @State private var tab: SettingsTab? = .script

    var body: some View {
        NavigationSplitView {
            // Rows are tagged with the tab itself. `List(data, selection:)` would tag
            // them with `SettingsTab.ID` — a String — and the binding would never match.
            List(selection: $tab) {
                ForEach(SettingsTab.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .padding(.vertical, 1)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 158, ideal: 172, max: 220)
            .safeAreaInset(edge: .bottom) {
                Text("NotchPrompter \(Self.appVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
        } detail: {
            detail
                .navigationTitle(tab?.title ?? "NotchPrompter")
                .toolbar { toolbarItems }
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    @ViewBuilder
    private var detail: some View {
        switch tab ?? .script {
        case .script: ScriptPane(settings: settings, controller: controller)
        case .appearance: AppearancePane(settings: settings)
        case .behavior: BehaviorPane(settings: settings)
        case .voice: VoicePane(settings: settings, controller: controller)
        case .shortcuts: ShortcutsPane()
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                controller.togglePlay()
            } label: {
                Image(systemName: controller.engine.isPlaying ? "pause.fill" : "play.fill")
            }
            .help(controller.engine.isPlaying ? "Pause scrolling" : "Start scrolling")

            Button {
                controller.toggleVisible()
            } label: {
                Image(systemName: controller.isVisible ? "eye" : "eye.slash")
            }
            .help(controller.isVisible ? "Hide prompter" : "Show prompter")

            Button {
                controller.restart()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("Back to start")
        }
    }

    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return version
    }
}

// MARK: - Shared rows

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { "\(Int($0))" }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                Text(format(value))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .trailing)
            }
        }
    }
}

struct ColorRow: View {
    let title: String
    @Binding var hex: String

    var body: some View {
        LabeledContent(title) {
            ColorPicker(
                "",
                selection: Binding(
                    get: { Color(hex: hex) },
                    set: { hex = $0.hexString }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
        }
    }
}
