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
    func activateToolSelection(_ tool: ToolKind)
    func undoLastChange()
    func redoLastChange()
    func clearAll(allowUndo: Bool)
    func setRadialControlVisible(_ isVisible: Bool)
    func setRadialDefaultPosition(_ position: RadialPosition)
    func setShortcutBindings(_ bindings: [ShortcutBinding])
    func setCommandHandler(_ handler: @escaping @MainActor (OverlayAction) -> Void)
    func setErrorHandler(_ handler: @escaping @MainActor (String) -> Void)
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
protocol RecordingService: AnyObject {
    var isRecording: Bool { get }
    var isPaused: Bool { get }
    var outputURL: URL? { get }
    var capturesSystemAudio: Bool { get set }
    /// Directory new recording files will be written to. Created on demand at
    /// `startRecording`. Default is `~/Movies/Pinnacle/`.
    var outputDirectory: URL { get set }
    func startRecording() throws
    func stopRecording() throws
    func pauseRecording() throws
    func resumeRecording() throws
    /// Awaits any in-flight finalization spawned by `stopRecording`.
    /// Call before app termination so the output file is durable.
    func awaitFinalization() async
    func setErrorHandler(_ handler: @escaping @MainActor (String) -> Void)
}

protocol PermissionService {
    func refreshPermissions() async -> PermissionStatus
    func requestScreenRecordingAccess()
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
