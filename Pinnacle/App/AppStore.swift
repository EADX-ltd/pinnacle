import Combine
import Foundation

enum CommandID: Equatable {
    case toggleAnnotation
    case startRecording
    case stopRecording
    case toggleRecording
    case pauseRecording
    case resumeRecording
    case selectTool(ToolKind)
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var sessionMode: SessionMode = .idle
    @Published private(set) var toolState: ToolState = .default
    @Published private(set) var lastErrorMessage: String?

    private let container: AppContainer
    private var modeBeforePause: SessionMode?

    init(container: AppContainer) {
        self.container = container
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
        modeBeforePause = nil
        switch sessionMode {
        case .recording:
            sessionMode = .idle
        case .recordingAndAnnotating:
            sessionMode = .annotating
        case .idle, .annotating, .paused:
            break
        }
    }
}
