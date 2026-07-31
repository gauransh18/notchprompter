import SwiftUI

struct ShortcutsPane: View {
    var store = ShortcutStore.shared

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent {
                        ShortcutRecorder(action: action)
                    } label: {
                        Label(action.title, systemImage: action.symbol)
                    }
                }
            } header: {
                Text("Global Shortcuts")
            } footer: {
                Text("These work anywhere, even while you are recording in another app. Every shortcut needs ⌘, ⌥ or ⌃.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Restore Default Shortcuts") {
                    store.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
    }
}
