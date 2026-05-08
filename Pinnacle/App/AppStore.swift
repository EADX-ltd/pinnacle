import Combine
import Foundation

enum CommandID: Equatable {
    case toggleAnnotation
    case startRecording
    case stopRecording
    case toggleRecording
    case pauseRecording
    case resumeRecording
    case togglePauseRecording
    case selectTool(ToolKind)
    case undo
    case redo
    case clearAll
    case cycleColors
    case increaseStroke
    case decreaseStroke
    case toggleRadialControl
}

@MainActor
final class AppStore: ObservableObject {
    static let shortcutBindingsPreferenceKey = PreferenceKey<[ShortcutBinding]>(
        name: "preferences.shortcuts.bindings",
        defaultValue: ShortcutBinding.defaults
    )
    static let toolConfigsPreferenceKey = PreferenceKey<[ToolKind: ToolConfig]>(
        name: "preferences.toolStyles.configs",
        defaultValue: ToolState.default.configs
    )
    static let toolExtendedOptionsPreferenceKey = PreferenceKey<[ToolKind: ToolExtendedOptions]>(
        name: "preferences.toolStyles.extendedOptions",
        defaultValue: ToolState.default.extendedOptions
    )
    static let radialControlEnabledPreferenceKey = PreferenceKey<Bool>(
        name: "preferences.radial.enabled",
        defaultValue: true
    )
    static let radialDefaultPositionPreferenceKey = PreferenceKey<RadialPosition>(
        name: "preferences.radial.defaultPosition",
        defaultValue: .right
    )
    static let preferencesSchemaVersionKey = PreferenceKey<Int>(
        name: "preferences.schemaVersion",
        defaultValue: 0  // 0 = legacy / never written
    )
    static let currentPreferencesSchemaVersion = 1
    /// Stored as POSIX path (String) rather than `URL` so older toolchains
    /// stay readable and the JSON encoding is human-inspectable. An empty
    /// string means "use the architecture default".
    static let outputDirectoryPathPreferenceKey = PreferenceKey<String>(
        name: "preferences.recording.outputDirectory",
        defaultValue: ""
    )

    @Published private(set) var sessionMode: SessionMode = .idle
    @Published private(set) var toolState: ToolState = .default
    @Published private(set) var lastErrorMessage: String?
    @Published var capturesSystemAudio: Bool = false {
        didSet {
            container.recordingService.capturesSystemAudio = capturesSystemAudio
        }
    }

    private let container: AppContainer
    private var modeBeforePause: SessionMode?
    private var isRadialControlVisible = true

    init(container: AppContainer) {
        self.container = container
        Self.migratePreferencesIfNeeded(using: container.preferencesService)
        // Load persisted tool styles before pushing to overlay so a fresh
        // session starts with the user's saved colors/widths instead of
        // defaults flashing through.
        toolState = Self.toolStateLoaded(from: container.preferencesService)
        isRadialControlVisible = container.preferencesService.value(for: Self.radialControlEnabledPreferenceKey)
        configureOverlay()
        configureShortcuts()
        configureRecording()
    }

    private static func migratePreferencesIfNeeded(using preferences: PreferencesService) {
        let stored = preferences.value(for: preferencesSchemaVersionKey)
        guard stored < currentPreferencesSchemaVersion else { return }
        // No migrations needed at v1 — the existing keys are already shaped
        // to the v1 schema. Future migrations branch on `stored`'s value here.
        preferences.setValue(currentPreferencesSchemaVersion, for: preferencesSchemaVersionKey)
    }

    private static func toolStateLoaded(from preferences: PreferencesService) -> ToolState {
        let savedConfigs = preferences.value(for: toolConfigsPreferenceKey)
        let savedExtOpts = preferences.value(for: toolExtendedOptionsPreferenceKey)
        var state = ToolState.default
        for tool in ToolKind.allCases {
            if let cfg = savedConfigs[tool] { state.configs[tool] = cfg }
            if let opts = savedExtOpts[tool] { state.extendedOptions[tool] = opts }
        }
        return state
    }

    func invalidate() {
        do {
            try container.shortcutService.unregisterAll()
        } catch {
            lastErrorMessage = "Failed to unregister shortcuts: \(error.localizedDescription)"
        }
    }

    var isAnnotating: Bool {
        sessionMode == .annotating || sessionMode == .recordingAndAnnotating
    }

    var isRecording: Bool {
        sessionMode == .recording || sessionMode == .recordingAndAnnotating || sessionMode == .paused
    }

    var menuBarSystemImage: String {
        switch sessionMode {
        case .idle:
            return "pencil.circle"
        case .annotating:
            return "pencil.circle.fill"
        case .recording:
            return "record.circle"
        case .recordingAndAnnotating:
            return "record.circle.fill"
        case .paused:
            return "pause.circle.fill"
        }
    }

    func send(_ command: CommandID) {
        do {
            try reduce(command)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func reduce(_ command: CommandID) throws {
        switch command {
        case .toggleAnnotation:
            try reduceAnnotationCommand(command)
        case .startRecording, .stopRecording, .toggleRecording,
             .pauseRecording, .resumeRecording, .togglePauseRecording:
            try reduceRecordingCommand(command)
        case .selectTool, .undo, .redo, .clearAll,
             .cycleColors, .increaseStroke, .decreaseStroke, .toggleRadialControl:
            try reduceToolCommand(command)
        }
    }

    private func reduceAnnotationCommand(_ command: CommandID) throws {
        guard case .toggleAnnotation = command else { return }
        switch sessionMode {
        case .idle:
            container.overlayService.startOverlay()
            sessionMode = .annotating
        case .annotating:
            container.overlayService.stopOverlay()
            sessionMode = .idle
        case .recording:
            container.overlayService.startOverlay()
            sessionMode = .recordingAndAnnotating
        case .recordingAndAnnotating:
            container.overlayService.stopOverlay()
            sessionMode = .recording
        case .paused:
            // Toggle annotation while paused stays in `.paused`; only the
            // pre-pause mode flips so resume returns the user to the matching
            // recording-and-annotating or recording-only state.
            if modeBeforePause == .recordingAndAnnotating {
                container.overlayService.stopOverlay()
                modeBeforePause = .recording
            } else {
                container.overlayService.startOverlay()
                modeBeforePause = .recordingAndAnnotating
            }
        }
    }

    private func reduceRecordingCommand(_ command: CommandID) throws {
        switch command {
        case .startRecording:
            try startRecording()
        case .stopRecording:
            try stopRecording()
        case .toggleRecording:
            if isRecording {
                try stopRecording()
            } else {
                try startRecording()
            }
        case .togglePauseRecording:
            if sessionMode == .paused {
                try reduceRecordingCommand(.resumeRecording)
            } else {
                try reduceRecordingCommand(.pauseRecording)
            }
        case .pauseRecording:
            guard sessionMode == .recording || sessionMode == .recordingAndAnnotating else { return }
            try container.recordingService.pauseRecording()
            modeBeforePause = sessionMode
            sessionMode = .paused
        case .resumeRecording:
            guard sessionMode == .paused else { return }
            try container.recordingService.resumeRecording()
            sessionMode = modeBeforePause ?? .recording
            modeBeforePause = nil
        default:
            break
        }
    }

    private func reduceToolCommand(_ command: CommandID) throws {
        switch command {
        case let .selectTool(tool):
            toolState.activeTool = tool
            container.overlayService.update(toolState: toolState)
            container.overlayService.activateToolSelection(tool)
        case .undo:
            container.overlayService.undoLastChange()
        case .redo:
            container.overlayService.redoLastChange()
        case .clearAll:
            container.overlayService.clearAll(allowUndo: true)
        case .cycleColors:
            let palette: [ColorHex] = ["#FF3B30FF", "#0A84FFFF", "#34C759FF", "#FFD60AFF", "#AF52DEFF", "#FFFFFFFF", "#FF9500FF"]
            guard var config = toolState.configs[toolState.activeTool] else { break }
            let idx = palette.firstIndex(of: config.colorHexRGBA) ?? -1
            config.colorHexRGBA = palette[(idx + 1) % palette.count]
            toolState.configs[toolState.activeTool] = config
            container.overlayService.update(toolState: toolState)
            persistToolStyle()
        case .increaseStroke:
            guard var config = toolState.configs[toolState.activeTool] else { break }
            config.strokeWidth = min(48, config.strokeWidth + 2)
            toolState.configs[toolState.activeTool] = config
            container.overlayService.update(toolState: toolState)
            persistToolStyle()
        case .decreaseStroke:
            guard var config = toolState.configs[toolState.activeTool] else { break }
            config.strokeWidth = max(1, config.strokeWidth - 2)
            toolState.configs[toolState.activeTool] = config
            container.overlayService.update(toolState: toolState)
            persistToolStyle()
        case .toggleRadialControl:
            isRadialControlVisible.toggle()
            container.overlayService.setRadialControlVisible(isRadialControlVisible)
            container.preferencesService.setValue(isRadialControlVisible, for: Self.radialControlEnabledPreferenceKey)
        default:
            break
        }
    }

    private func startRecording() throws {
        guard !isRecording else { return }
        try container.recordingService.startRecording()
        switch sessionMode {
        case .idle:
            sessionMode = .recording
        case .annotating:
            sessionMode = .recordingAndAnnotating
        case .recording, .recordingAndAnnotating, .paused:
            break
        }
    }

    private func stopRecording() throws {
        guard isRecording else { return }
        try container.recordingService.stopRecording()
        switch sessionMode {
        case .recording:
            modeBeforePause = nil
            sessionMode = .idle
        case .recordingAndAnnotating:
            modeBeforePause = nil
            sessionMode = .annotating
        case .paused:
            let pausedFromMode = modeBeforePause
            modeBeforePause = nil
            if pausedFromMode == .recordingAndAnnotating {
                sessionMode = .annotating
            } else {
                sessionMode = .idle
            }
        case .idle, .annotating:
            break
        }
    }

    var currentShortcutBindings: [ShortcutBinding] {
        container.preferencesService.value(for: Self.shortcutBindingsPreferenceKey)
    }

    /// Validates the proposed bindings, re-registers them with the shortcut
    /// service, and persists on success. Returns `true` if applied, `false` if
    /// the bindings conflict or registration failed (with `lastErrorMessage`
    /// set in either case).
    @discardableResult
    func updateShortcutBindings(_ bindings: [ShortcutBinding]) -> Bool {
        guard !ShortcutConflictValidator.containsConflicts(bindings) else {
            lastErrorMessage = "Two or more shortcuts share the same key combination."
            return false
        }
        do {
            try container.shortcutService.register(bindings: bindings, handler: makeShortcutHandler())
            container.preferencesService.setValue(bindings, for: Self.shortcutBindingsPreferenceKey)
            container.overlayService.setShortcutBindings(bindings)
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = "Failed to register shortcuts: \(error.localizedDescription)"
            return false
        }
    }

    var isRadialControlEnabled: Bool { isRadialControlVisible }

    func setRadialControlEnabled(_ enabled: Bool) {
        isRadialControlVisible = enabled
        container.overlayService.setRadialControlVisible(enabled)
        container.preferencesService.setValue(enabled, for: Self.radialControlEnabledPreferenceKey)
    }

    var radialDefaultPosition: RadialPosition {
        container.preferencesService.value(for: Self.radialDefaultPositionPreferenceKey)
    }

    func setRadialDefaultPosition(_ position: RadialPosition) {
        container.overlayService.setRadialDefaultPosition(position)
        container.preferencesService.setValue(position, for: Self.radialDefaultPositionPreferenceKey)
    }

    /// Restore shortcut bindings to architecture defaults, persist, and
    /// re-register with the shortcut service.
    func resetShortcutsToDefaults() {
        _ = updateShortcutBindings(ShortcutBinding.defaults)
    }

    /// Restore all per-tool styles (configs + extended options) to the
    /// architecture defaults, push to the overlay, and persist.
    func resetToolStylesToDefaults() {
        toolState.configs = ToolState.default.configs
        toolState.extendedOptions = ToolState.default.extendedOptions
        container.overlayService.update(toolState: toolState)
        persistToolStyle()
    }

    /// Current screen-recording permission status, computed via the live
    /// PermissionService. Async because the underlying TCC API is async-shaped.
    func permissionStatus() async -> PermissionStatus {
        await container.permissionService.refreshPermissions()
    }

    /// Triggers the screen-recording TCC prompt the first time, and records
    /// internally that a request has been made so subsequent preflight=false
    /// readings can be reported as `.denied` rather than `.notDetermined`.
    func requestScreenRecordingAccess() {
        container.permissionService.requestScreenRecordingAccess()
    }

    func currentToolConfig(for tool: ToolKind) -> ToolConfig {
        toolState.configs[tool]
            ?? ToolState.default.configs[tool]
            ?? ToolConfig(colorHexRGBA: "#FFD60AFF", strokeWidth: 1, opacity: 1)
    }

    func currentToolExtendedOptions(for tool: ToolKind) -> ToolExtendedOptions {
        toolState.extendedOptions[tool] ?? .default
    }

    /// Update one tool's color/stroke/opacity. Pushes to the overlay service
    /// (so an open radial picks it up) and persists.
    func updateToolConfig(_ config: ToolConfig, for tool: ToolKind) {
        toolState.configs[tool] = config
        container.overlayService.update(toolState: toolState)
        persistToolStyle()
    }

    /// Update one tool's extended options (line/arrow/font). Pushes to the
    /// overlay service and persists.
    func updateToolExtendedOptions(_ options: ToolExtendedOptions, for tool: ToolKind) {
        toolState.extendedOptions[tool] = options
        container.overlayService.update(toolState: toolState)
        persistToolStyle()
    }

    private func persistToolStyle() {
        container.preferencesService.setValue(
            toolState.configs,
            for: Self.toolConfigsPreferenceKey
        )
        container.preferencesService.setValue(
            toolState.extendedOptions,
            for: Self.toolExtendedOptionsPreferenceKey
        )
    }

    private func makeShortcutHandler() -> @MainActor (ShortcutCommandID) -> Void {
        { [weak self] shortcutCommand in
            guard let self else { return }
            send(command(for: shortcutCommand))
        }
    }

    private func configureShortcuts() {
        let storedBindings = container.preferencesService.value(for: Self.shortcutBindingsPreferenceKey)
        let hadConflicts = ShortcutConflictValidator.containsConflicts(storedBindings)
        let resolvedBindings = ShortcutConflictValidator.resolvedBindings(storedBindings)

        do {
            try container.shortcutService.register(bindings: resolvedBindings, handler: makeShortcutHandler())
            // Only persist when the stored bindings were already conflict-free,
            // so a transient conflict (e.g. from an app update introducing a
            // new default) doesn't permanently overwrite user customizations.
            if !hadConflicts {
                container.preferencesService.setValue(resolvedBindings, for: Self.shortcutBindingsPreferenceKey)
            } else {
                lastErrorMessage = "Some saved shortcuts conflicted; using defaults for this session. Resolve the conflict in Settings to persist your customizations."
            }
            container.overlayService.setShortcutBindings(resolvedBindings)
        } catch {
            lastErrorMessage = "Failed to register shortcuts: \(error.localizedDescription)"
        }
    }

    var outputDirectory: URL {
        let stored = container.preferencesService.value(for: Self.outputDirectoryPathPreferenceKey)
        if !stored.isEmpty {
            return URL(fileURLWithPath: stored, isDirectory: true)
        }
        return ScreenCaptureKitRecordingService.defaultOutputDirectory()
    }

    enum OutputDirectoryError: LocalizedError, Equatable {
        case notADirectory
        case notWritable(String)

        var errorDescription: String? {
            switch self {
            case .notADirectory:
                return "Selected path is not a directory."
            case .notWritable(let detail):
                return "Selected directory cannot be written to: \(detail)"
            }
        }
    }

    /// Validate the chosen directory and apply it to both the live recording
    /// service and persisted preferences. Throws if the path doesn't exist
    /// or fails a probe write so the caller can surface the failure in the
    /// UI. The probe is a tiny temporary file (created and immediately
    /// deleted) — `FileManager.isWritableFile` is best-effort and reports
    /// true for some unwritable network/ACL paths.
    func setOutputDirectory(_ url: URL) throws {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if exists, !isDir.boolValue {
            throw OutputDirectoryError.notADirectory
        }
        if !exists {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let probe = url.appendingPathComponent(".pinnacle_writability_probe", isDirectory: false)
        do {
            try Data().write(to: probe, options: .atomic)
            try FileManager.default.removeItem(at: probe)
        } catch {
            throw OutputDirectoryError.notWritable(error.localizedDescription)
        }
        container.recordingService.outputDirectory = url
        container.preferencesService.setValue(url.path, for: Self.outputDirectoryPathPreferenceKey)
    }

    /// Restore the recording output directory to the architecture default.
    func resetOutputDirectory() {
        let defaultURL = ScreenCaptureKitRecordingService.defaultOutputDirectory()
        container.recordingService.outputDirectory = defaultURL
        container.preferencesService.setValue("", for: Self.outputDirectoryPathPreferenceKey)
    }

    private func configureRecording() {
        container.recordingService.capturesSystemAudio = capturesSystemAudio
        // Apply persisted output directory (falls back to default if unset or
        // missing). Validation happens on `setOutputDirectory`; here we trust
        // the persisted value and only fall back if the path is gone.
        let stored = container.preferencesService.value(for: Self.outputDirectoryPathPreferenceKey)
        if !stored.isEmpty {
            let url = URL(fileURLWithPath: stored, isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                container.recordingService.outputDirectory = url
            }
        }
        container.recordingService.setErrorHandler { [weak self] message in
            guard let self else { return }
            lastErrorMessage = message
            guard isRecording else { return }
            // Capture pre-pause mode before clearing so the .paused branch can
            // route back to the right post-error state (overlay stays running
            // when paused-from `.recordingAndAnnotating`).
            let pausedFromMode = modeBeforePause
            modeBeforePause = nil
            switch sessionMode {
            case .recording:
                sessionMode = .idle
            case .recordingAndAnnotating:
                sessionMode = .annotating
            case .paused:
                sessionMode = pausedFromMode == .recordingAndAnnotating ? .annotating : .idle
            default:
                break
            }
        }
    }

    private func configureOverlay() {
        container.overlayService.update(toolState: toolState)
        container.overlayService.setRadialControlVisible(isRadialControlVisible)
        container.overlayService.setRadialDefaultPosition(
            container.preferencesService.value(for: Self.radialDefaultPositionPreferenceKey)
        )
        container.overlayService.setErrorHandler { [weak self] message in
            self?.lastErrorMessage = message
        }
        container.overlayService.setCommandHandler { [weak self] action in
            guard let self else { return }
            switch action {
            case let .selectTool(tool):
                send(.selectTool(tool))
            case .undo:
                send(.undo)
            case .redo:
                send(.redo)
            case .clearAll:
                send(.clearAll)
            case .cycleColors:
                send(.cycleColors)
            case .increaseStroke:
                send(.increaseStroke)
            case .decreaseStroke:
                send(.decreaseStroke)
            case let .applyToolOptions(tool, config, extendedOptions):
                toolState.configs[tool] = config
                toolState.extendedOptions[tool] = extendedOptions
                container.overlayService.update(toolState: toolState)
                persistToolStyle()
            }
        }
    }

    private func command(for shortcutCommand: ShortcutCommandID) -> CommandID {
        switch shortcutCommand {
        case .toggleAnnotation:
            return .toggleAnnotation
        case .toggleRecording:
            return .toggleRecording
        case .togglePauseRecording:
            return .togglePauseRecording
        case .selectPen:
            return .selectTool(.pen)
        case .selectHighlighter:
            return .selectTool(.highlighter)
        case .selectArrow:
            return .selectTool(.arrow)
        case .selectRectangle:
            return .selectTool(.rectangle)
        case .selectEllipse:
            return .selectTool(.ellipse)
        case .selectText:
            return .selectTool(.text)
        case .selectEraser:
            return .selectTool(.eraser)
        case .undo:
            return .undo
        case .redo:
            return .redo
        case .clearAll:
            return .clearAll
        case .cycleColors:
            return .cycleColors
        case .increaseStroke:
            return .increaseStroke
        case .decreaseStroke:
            return .decreaseStroke
        case .toggleRadialControl:
            return .toggleRadialControl
        }
    }
}
