import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        TabView {
            ShortcutEditorView(store: store)
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

// No SwiftUI #Preview here on purpose: see ShortcutEditorView for rationale.
