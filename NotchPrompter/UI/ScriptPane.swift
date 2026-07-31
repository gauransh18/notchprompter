import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScriptPane: View {
    @Bindable var settings: AppSettings
    var controller: PrompterController

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $settings.script)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .padding(.horizontal, 4)

            Divider()

            footer
        }
        .background(Color(nsColor: .textBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Button("Insert [Pause]") { insert("\n[Pause]\n") }
                    Button("Insert [Short Pause]") { insert("\n[Short Pause]\n") }
                    Divider()
                    Button("Import from File…", action: importScript)
                    Button("Export to File…", action: exportScript)
                    Divider()
                    Button("Load Sample Script") { settings.script = AppSettings.sampleScript }
                    Button("Clear Script", role: .destructive) { settings.script = "" }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Script actions")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label("\(settings.wordCount) words", systemImage: "textformat.abc")
            Label(readingTime, systemImage: "clock")
            Label(scrollTime, systemImage: "arrow.down.circle")

            Spacer()

            Text("Bracketed lines like [Pause] are shown but skipped by voice follow.")
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var readingTime: String {
        format(settings.estimatedDuration) + " read"
    }

    /// How long the current scroll speed will take to walk the whole script.
    private var scrollTime: String {
        let height = controller.engine.contentHeight - controller.engine.viewportHeight
        guard height > 0, settings.scrollSpeed > 0 else { return "—" }
        return format(height / settings.scrollSpeed) + " at current speed"
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func insert(_ text: String) {
        settings.script += text
    }

    private func importScript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text, .rtf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if url.pathExtension.lowercased() == "rtf",
           let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
            settings.script = attributed.string
            return
        }
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            settings.script = text
        }
    }

    private func exportScript() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "script.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? settings.script.write(to: url, atomically: true, encoding: .utf8)
    }
}
