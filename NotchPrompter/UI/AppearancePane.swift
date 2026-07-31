import AppKit
import SwiftUI

struct AppearancePane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Script") {
                LabeledContent("Font style") {
                    FontStylePicker(selection: $settings.fontStyle)
                }

                SliderRow(title: "Font size", value: $settings.fontSize, range: 9...48) { "\(Int($0)) pt" }
                SliderRow(title: "Line spacing", value: $settings.lineSpacing, range: 0...20) { "\(Int($0)) pt" }

                LabeledContent("Alignment") {
                    Picker("", selection: $settings.alignment) {
                        ForEach(TextAlign.allCases) { align in
                            Image(systemName: align.symbol).tag(align)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            Section("Prompter Window") {
                SliderRow(title: "Width", value: $settings.panelWidth, range: 200...1400) { "\(Int($0)) px" }
                SliderRow(title: "Height", value: $settings.panelHeight, range: 40...700) { "\(Int($0)) px" }
                SliderRow(title: "Top offset", value: $settings.verticalOffset, range: 0...400) { "\(Int($0)) px" }

                LabeledContent("Position") {
                    Picker("", selection: $settings.position) {
                        ForEach(PanelPosition.allCases) { position in
                            Text(position.label).tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Picker("Target screen", selection: $settings.screenID) {
                    Text("Automatic").tag("")
                    ForEach(NSScreen.screens, id: \.persistentIdentifier) { screen in
                        Text(screenLabel(screen)).tag(screen.persistentIdentifier)
                    }
                }

                if settings.position == .custom {
                    Text("Drag the prompter itself to move it. Turn off click-through first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Visuals") {
                SliderRow(title: "Background opacity", value: $settings.backgroundOpacity, range: 0...1, step: 0.01) {
                    "\(Int($0 * 100))%"
                }
                SliderRow(title: "Corner radius", value: $settings.cornerRadius, range: 0...40) { "\(Int($0)) px" }

                ColorRow(title: "Text color", hex: $settings.textColorHex)
                ColorRow(title: "Background color", hex: $settings.backgroundColorHex)
                ColorRow(title: "Spoken line color", hex: $settings.highlightColorHex)

                Toggle("Fade top and bottom edges", isOn: $settings.fadeEdges)
                Toggle("Dim lines you have not reached", isOn: $settings.dimUnreadLines)
                Toggle("Mirror text (for teleprompter glass)", isOn: $settings.mirrorText)
            }

            Section {
                Button("Reset Appearance to Defaults") {
                    settings.resetAppearance()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func screenLabel(_ screen: NSScreen) -> String {
        let notch = NotchGeometry.hasNotch(screen) ? " · has notch" : ""
        return "\(screen.localizedName)\(notch)"
    }
}

// MARK: - Font style picker

struct FontStylePicker: View {
    @Binding var selection: FontStyle

    var body: some View {
        HStack(spacing: 6) {
            ForEach(FontStyle.allCases) { style in
                let isSelected = selection == style

                Button {
                    selection = style
                } label: {
                    VStack(spacing: 1) {
                        Text("Ab")
                            .font(.system(size: 14, weight: style.weight, design: style.design))
                        Text(style.label)
                            .font(.system(size: 9))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .frame(width: 48, height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.9) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.12))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .help(style.label)
            }
        }
    }
}
