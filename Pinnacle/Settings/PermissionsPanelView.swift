import AppKit
import SwiftUI

struct PermissionsPanelView: View {
    @ObservedObject var store: AppStore
    @State private var status: PermissionStatus = .notDetermined
    @State private var isChecking = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Image(systemName: statusSymbol)
                            .foregroundStyle(statusColor)
                        Text(statusText)
                    }
                }
                LabeledContent("Why this is needed") {
                    Text("Pinnacle needs Screen Recording access to capture the display under your cursor when you start a recording. Annotations are an overlay on top of the captured image and don't transmit anywhere.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Screen Recording")
            }

            Section {
                HStack {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isChecking {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Re-check")
                        }
                    }
                    .disabled(isChecking)

                    Button("Request Access") {
                        store.requestScreenRecordingAccess()
                        Task { await refresh() }
                    }
                    .disabled(status == .granted)

                    Button("Open System Settings") {
                        openScreenRecordingPreferencePane()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .task { await refresh() }
    }

    private var statusSymbol: String {
        switch status {
        case .granted: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        }
    }

    private var statusText: String {
        switch status {
        case .granted:
            return "Granted — recording is enabled."
        case .denied:
            return "Denied — open System Settings to grant access."
        case .notDetermined:
            return "Not yet requested — click Request Access to prompt."
        }
    }

    private func refresh() async {
        isChecking = true
        status = await store.permissionStatus()
        isChecking = false
    }

    private func openScreenRecordingPreferencePane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

// No SwiftUI #Preview here on purpose: see ShortcutEditorView for rationale.
