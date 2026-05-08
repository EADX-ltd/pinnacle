import Foundation
@testable import Pinnacle

@MainActor
struct NoOpShortcutService: ShortcutService {
    func register(bindings: [ShortcutBinding], handler: @escaping @MainActor (ShortcutCommandID) -> Void) throws {}
    func unregisterAll() throws {}
}

@MainActor
struct NoOpOverlayService: OverlayService {
    func startOverlay() {}
    func stopOverlay() {}
    func update(toolState: ToolState) {}
    func activateToolSelection(_ tool: ToolKind) {}
    func undoLastChange() {}
    func redoLastChange() {}
    func clearAll(allowUndo: Bool) {}
    func setRadialControlVisible(_ isVisible: Bool) {}
    func setRadialDefaultPosition(_ position: RadialPosition) {}
    func setShortcutBindings(_ bindings: [ShortcutBinding]) {}
    func setCommandHandler(_ handler: @escaping @MainActor (OverlayAction) -> Void) {}
    func setErrorHandler(_ handler: @escaping @MainActor (String) -> Void) {}
}

@MainActor
final class InMemoryRecordingService: RecordingService {
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var outputURL: URL?
    var capturesSystemAudio: Bool = false

    func startRecording() throws {
        isRecording = true
        isPaused = false
    }

    func stopRecording() throws {
        isRecording = false
        isPaused = false
    }

    func pauseRecording() throws {
        guard isRecording else { return }
        isPaused = true
    }

    func resumeRecording() throws {
        guard isRecording else { return }
        isPaused = false
    }

    func awaitFinalization() async {}

    func setErrorHandler(_ handler: @escaping @MainActor (String) -> Void) {}
}

struct NoOpPermissionService: PermissionService {
    func refreshPermissions() async -> PermissionStatus {
        .notDetermined
    }

    func requestScreenRecordingAccess() {}
}
