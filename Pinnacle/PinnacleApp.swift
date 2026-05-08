//
//  PinnacleApp.swift
//  Pinnacle
//
//  Created by Zhivko Poroyliev on 31.03.26.
//

import SwiftUI
import AppKit

@MainActor
@main
struct PinnacleApp: App {
    @NSApplicationDelegateAdaptor(PinnacleAppDelegate.self) private var appDelegate
    @StateObject private var store: AppStore

    init() {
        let liveContainer = AppContainer.live
        _store = StateObject(wrappedValue: AppStore(container: liveContainer))
    }

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 12) {
                Label(store.sessionMode.displayName, systemImage: store.menuBarSystemImage)
                    .font(.headline)

                Divider()

                Button(store.isAnnotating ? "Stop Annotation" : "Start Annotation") {
                    store.send(.toggleAnnotation)
                }

                Button(store.isRecording ? "Stop Recording" : "Start Recording") {
                    store.send(.toggleRecording)
                }

                if let error = store.lastErrorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                Button("Quit Pinnacle") {
                    store.invalidate()
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 4)
            .frame(width: 240)
        } label: {
            Label("Pinnacle", systemImage: store.menuBarSystemImage)
        }

        Settings {
            SettingsView(store: store)
        }

#if DEBUG
        WindowGroup("Pinnacle Debug") {
            ContentView(container: .live)
        }
#endif
    }
}

@MainActor
final class PinnacleAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let recordingService = AppContainer.live.recordingService
        if recordingService.isRecording {
            try? recordingService.stopRecording()
        }
        Task { @MainActor in
            await recordingService.awaitFinalization()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
