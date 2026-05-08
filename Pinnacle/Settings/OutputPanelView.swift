import AppKit
import SwiftUI

struct OutputPanelView: View {
    @ObservedObject var store: AppStore
    @State private var errorMessage: String?

    private var directoryDisplay: String {
        store.outputDirectory.path
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Recording folder") {
                    HStack {
                        Text(directoryDisplay)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([store.outputDirectory])
                        }
                    }
                }
                LabeledContent("File naming") {
                    Text("Pinnacle-yyyyMMdd-HHmmss.mp4 — collisions append `-1`, `-2`, … so a recording never overwrites an existing file.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Recording Output")
            }

            Section {
                HStack {
                    Button("Choose Folder…") { presentFolderPicker() }
                    Button("Reset to Default") {
                        store.resetOutputDirectory()
                        errorMessage = nil
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }

    private func presentFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose where Pinnacle should save recordings"
        panel.prompt = "Choose"
        panel.directoryURL = store.outputDirectory

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.setOutputDirectory(url)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// No SwiftUI #Preview here on purpose: see ShortcutEditorView for rationale.
