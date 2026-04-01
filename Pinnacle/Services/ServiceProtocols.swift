import Foundation

@MainActor
protocol ShortcutService {
    func register(bindings: [ShortcutBinding], handler: @escaping @MainActor (ShortcutCommandID) -> Void) throws
    func unregisterAll() throws
}

@MainActor
protocol OverlayService {
    func startOverlay()
    func stopOverlay()
    func update(toolState: ToolState)
    func undoLastChange()
    func redoLastChange()
    func clearAll(allowUndo: Bool)
    func setRadialControlVisible(_ isVisible: Bool)
    func setShortcutBindings(_ bindings: [ShortcutBinding])
    func setCommandHandler(_ handler: @escaping @MainActor (OverlayAction) -> Void)
}

enum OverlayAction: Equatable {
    case selectTool(ToolKind)
    case undo
    case redo
    case clearAll
    case cycleColors
    case increaseStroke
    case decreaseStroke
    case applyToolOptions(ToolKind, ToolConfig, ToolExtendedOptions)
}

@MainActor
protocol RecordingService {
    var isRecording: Bool { get }
    func startRecording() throws
    func stopRecording() throws
}

protocol PermissionService {
    func refreshPermissions() async -> PermissionStatus
}

@MainActor
protocol PreferencesService {
    func value<T: Codable>(for key: PreferenceKey<T>) -> T
    func setValue<T: Codable>(_ value: T, for key: PreferenceKey<T>)
}

enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
}

struct PreferenceKey<Value: Codable> {
    let name: String
    let defaultValue: Value
}
