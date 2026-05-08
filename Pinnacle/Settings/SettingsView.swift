import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        TabView {
            ShortcutEditorView(store: store)
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
            ToolStyleEditorView(store: store)
                .tabItem {
                    Label("Tools", systemImage: "paintbrush.pointed")
                }
            RadialControlPanelView(store: store)
                .tabItem {
                    Label("Radial", systemImage: "circle.grid.2x2")
                }
            PermissionsPanelView(store: store)
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

// No SwiftUI #Preview here on purpose: see ShortcutEditorView for rationale.
