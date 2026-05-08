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
        configureOverlay()
        configureShortcuts()
        configureRecording()
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
        case .increaseStroke:
            guard var config = toolState.configs[toolState.activeTool] else { break }
            config.strokeWidth = min(48, config.strokeWidth + 2)
            toolState.configs[toolState.activeTool] = config
            container.overlayService.update(toolState: toolState)
        case .decreaseStroke:
            guard var config = toolState.configs[toolState.activeTool] else { break }
            config.strokeWidth = max(1, config.strokeWidth - 2)
            toolState.configs[toolState.activeTool] = config
            container.overlayService.update(toolState: toolState)
        case .toggleRadialControl:
            isRadialControlVisible.toggle()
            container.overlayService.setRadialControlVisible(isRadialControlVisible)
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

    private func configureShortcuts() {
        let storedBindings = container.preferencesService.value(for: Self.shortcutBindingsPreferenceKey)
        let hadConflicts = ShortcutConflictValidator.containsConflicts(storedBindings)
        let resolvedBindings = ShortcutConflictValidator.resolvedBindings(storedBindings)

        do {
            try container.shortcutService.register(bindings: resolvedBindings) { [weak self] shortcutCommand in
                guard let self else { return }
                send(command(for: shortcutCommand))
            }
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

    private func configureRecording() {
        container.recordingService.capturesSystemAudio = capturesSystemAudio
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
