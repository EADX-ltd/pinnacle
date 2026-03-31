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

    private let container: AppContainer
    private var modeBeforePause: SessionMode?

    init(container: AppContainer) {
        self.container = container
        configureShortcuts()
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

    var canToggleAnnotation: Bool {
        sessionMode != .paused
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
                // Intentional until recording engine pause/resume is wired.
                break
            }
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
                try reduce(.resumeRecording)
            } else {
                try reduce(.pauseRecording)
            }
        case .pauseRecording:
            // TODO: Wire pauseRecording to concrete RecordingService in recording phase.
            guard sessionMode == .recording || sessionMode == .recordingAndAnnotating else { return }
            modeBeforePause = sessionMode
            sessionMode = .paused
        case .resumeRecording:
            // TODO: Wire resumeRecording to concrete RecordingService in recording phase.
            guard sessionMode == .paused else { return }
            sessionMode = modeBeforePause ?? .recording
            modeBeforePause = nil
        case let .selectTool(tool):
            toolState.activeTool = tool
        case .undo:
            // TODO: Wire undo once command stack is introduced in Phase 4.
            break
        case .redo:
            // TODO: Wire redo once command stack is introduced in Phase 4.
            break
        case .clearAll:
            // TODO: Wire clear-all once renderer model is introduced in Phase 4.
            break
        case .cycleColors:
            // TODO: Wire palette cycling in settings/rendering phase.
            break
        case .increaseStroke:
            // TODO: Wire stroke width mutation in tool configuration flow.
            break
        case .decreaseStroke:
            // TODO: Wire stroke width mutation in tool configuration flow.
            break
        case .toggleRadialControl:
            // TODO: Wire radial control visibility in overlay phase.
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
        let resolvedBindings = ShortcutConflictValidator.resolvedBindings(storedBindings)

        do {
            try container.shortcutService.register(bindings: resolvedBindings) { [weak self] shortcutCommand in
                guard let self else { return }
                send(command(for: shortcutCommand))
            }
            container.preferencesService.setValue(resolvedBindings, for: Self.shortcutBindingsPreferenceKey)
        } catch {
            lastErrorMessage = "Failed to register shortcuts: \(error.localizedDescription)"
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
