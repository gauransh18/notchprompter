import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, press a combo, done. Escape cancels, Delete clears.
struct ShortcutRecorder: View {
    let action: ShortcutAction

    @State private var isRecording = false
    @State private var monitor: Any?

    private var store = ShortcutStore.shared

    init(action: ShortcutAction) {
        self.action = action
    }

    private var combo: KeyCombo? { store.combo(for: action) }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 78)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)

            Button {
                store.set(nil, for: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(combo == nil ? 0 : 1)
            .disabled(combo == nil)
            .help("Clear shortcut")
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording { return "Press keys…" }
        return combo?.display ?? "Not set"
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control, .shift])

        switch Int(event.keyCode) {
        case kVK_Escape:
            stopRecording()
            return
        case kVK_Delete, kVK_ForwardDelete:
            store.set(nil, for: action)
            stopRecording()
            return
        default:
            break
        }

        let candidate = KeyCombo(keyCode: event.keyCode, modifiers: flags.rawValue)
        guard candidate.isValid else {
            NSSound.beep()
            return
        }

        store.set(candidate, for: action)
        stopRecording()
    }
}
