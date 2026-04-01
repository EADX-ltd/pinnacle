import Foundation

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
    func undoLastChange() {}
    func redoLastChange() {}
    func clearAll(allowUndo: Bool) {}
    func setRadialControlVisible(_ isVisible: Bool) {}
    func setShortcutBindings(_ bindings: [ShortcutBinding]) {}
    func setCommandHandler(_ handler: @escaping @MainActor (OverlayAction) -> Void) {}
}

@MainActor
final class InMemoryRecordingService: RecordingService {
    private(set) var isRecording = false

    func startRecording() throws {
        isRecording = true
    }

    func stopRecording() throws {
        isRecording = false
    }
}

struct NoOpPermissionService: PermissionService {
    func refreshPermissions() async -> PermissionStatus {
        .notDetermined
    }
}
