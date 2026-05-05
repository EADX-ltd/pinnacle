import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit

enum RecordingError: LocalizedError {
    case noDisplay
    case permissionRequired

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "No display available for recording."
        case .permissionRequired:
            return "Screen recording permission is required. Grant access in System Settings → Privacy & Security → Screen Recording, then restart the app."
        }
    }
}

@MainActor
final class ScreenCaptureKitRecordingService: NSObject, RecordingService {
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var outputURL: URL?
    var capturesSystemAudio: Bool = false {
        didSet {
            if isRecording {
                log.info("capturesSystemAudio change ignored while recording is active")
            }
        }
    }

    private var stream: SCStream?
    private var pipeline: AVAssetWriterPipeline?
    private var streamOutputAdapter: StreamOutputAdapter?
    private var errorHandler: (@MainActor (String) -> Void)?

    private let videoQueue = DispatchQueue(label: "com.pinnacle.recording.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.pinnacle.recording.audio", qos: .userInteractive)
    private let log = Logger(subsystem: "com.pinnacle", category: "recording")

    func setErrorHandler(_ handler: @escaping @MainActor (String) -> Void) {
        errorHandler = handler
    }

    func startRecording() throws {
        guard !isRecording else { return }

        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw RecordingError.permissionRequired
        }

        guard let display = DisplayDescriptor.underMouse() else {
            throw RecordingError.noDisplay
        }

        let url = makeOutputURL()
        let pixelWidth = Int(display.frame.width * display.scaleFactor)
        let pixelHeight = Int(display.frame.height * display.scaleFactor)

        let pipeline = try AVAssetWriterPipeline(
            outputURL: url,
            width: pixelWidth,
            height: pixelHeight,
            captureAudio: capturesSystemAudio
        )
        try pipeline.startWriting()

        self.pipeline = pipeline
        self.outputURL = url
        self.isRecording = true
        self.isPaused = false

        let captureAudio = capturesSystemAudio
        let displayID = display.id
        let frame = display.frame
        let scale = display.scaleFactor

        log.info("Starting recording to \(url.path, privacy: .public) (display=\(displayID), audio=\(captureAudio, privacy: .public))")

        Task { [weak self] in
            await self?.beginCapture(
                displayID: displayID,
                frame: frame,
                scale: scale,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                captureAudio: captureAudio,
                pipeline: pipeline
            )
        }
    }

    func stopRecording() throws {
        guard isRecording else { return }
        let stream = self.stream
        let pipeline = self.pipeline
        let url = self.outputURL

        self.isRecording = false
        self.isPaused = false
        self.stream = nil
        self.pipeline = nil
        self.streamOutputAdapter = nil

        log.info("Stopping recording")

        Task { [log, errorHandler] in
            if let stream {
                do {
                    try await stream.stopCapture()
                } catch {
                    log.error("Stream stop error: \(error.localizedDescription, privacy: .public)")
                    await MainActor.run {
                        errorHandler?("Recording stream stop failed: \(error.localizedDescription)")
                    }
                }
            }
            await pipeline?.finish()
            if let url {
                log.info("Recording finalized at \(url.path, privacy: .public)")
            }
        }
    }

    func pauseRecording() throws {
        guard isRecording, !isPaused else { return }
        isPaused = true
        pipeline?.setPaused(true)
        log.info("Recording paused")
    }

    func resumeRecording() throws {
        guard isRecording, isPaused else { return }
        isPaused = false
        pipeline?.setPaused(false)
        log.info("Recording resumed")
    }

    private func beginCapture(
        displayID: CGDirectDisplayID,
        frame: CGRect,
        scale: CGFloat,
        pixelWidth: Int,
        pixelHeight: Int,
        captureAudio: Bool,
        pipeline: AVAssetWriterPipeline
    ) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
                await fail(message: "Selected display is not available for capture")
                return
            }

            let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
            let cfg = SCStreamConfiguration()
            cfg.width = pixelWidth
            cfg.height = pixelHeight
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            cfg.queueDepth = 8
            cfg.pixelFormat = kCVPixelFormatType_32BGRA
            cfg.colorSpaceName = CGColorSpace.sRGB
            cfg.showsCursor = true
            if #available(macOS 13.0, *) {
                cfg.capturesAudio = captureAudio
            }

            let adapter = StreamOutputAdapter(pipeline: pipeline)
            let stream = SCStream(filter: filter, configuration: cfg, delegate: adapter)
            try stream.addStreamOutput(adapter, type: .screen, sampleHandlerQueue: videoQueue)
            if #available(macOS 13.0, *), captureAudio {
                try stream.addStreamOutput(adapter, type: .audio, sampleHandlerQueue: audioQueue)
            }

            adapter.onUnexpectedStop = { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.fail(message: message)
                }
            }

            try await stream.startCapture()

            await MainActor.run {
                guard self.isRecording else {
                    Task { try? await stream.stopCapture() }
                    return
                }
                self.stream = stream
                self.streamOutputAdapter = adapter
            }
        } catch {
            await fail(message: "Failed to start capture: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func fail(message: String) {
        log.error("\(message, privacy: .public)")
        errorHandler?(message)
        isRecording = false
        isPaused = false
        let pipeline = self.pipeline
        self.pipeline = nil
        self.stream = nil
        self.streamOutputAdapter = nil
        Task {
            await pipeline?.finish()
        }
    }

    private func makeOutputURL() -> URL {
        let base = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Pinnacle", isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let name = "Pinnacle-\(formatter.string(from: Date())).mp4"
        return dir.appendingPathComponent(name)
    }
}

private final class StreamOutputAdapter: NSObject, SCStreamDelegate, SCStreamOutput {
    var onUnexpectedStop: ((String) -> Void)?
    private let pipeline: AVAssetWriterPipeline

    init(pipeline: AVAssetWriterPipeline) {
        self.pipeline = pipeline
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        switch type {
        case .screen:
            guard
                let attachments = CMSampleBufferGetSampleAttachmentsArray(
                    sampleBuffer,
                    createIfNecessary: false
                ) as? [[SCStreamFrameInfo: Any]],
                let info = attachments.first,
                let statusRaw = info[.status] as? Int,
                let status = SCFrameStatus(rawValue: statusRaw),
                status == .complete
            else { return }
            pipeline.appendVideo(sampleBuffer)
        case .audio:
            pipeline.appendAudio(sampleBuffer)
        @unknown default:
            return
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onUnexpectedStop?("Capture stopped unexpectedly: \(error.localizedDescription)")
    }
}
