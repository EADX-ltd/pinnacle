import AVFoundation
import CoreMedia
import Foundation

/// Thread-safe wrapper around `AVAssetWriter` for screen recording.
///
/// Sample append calls are expected from the SCStreamOutput dispatch queue (off the main
/// actor). Internal state is guarded by `NSLock` so that concurrent append/finish/pause
/// calls from any queue are safe.
final class AVAssetWriterPipeline {
    enum PipelineError: LocalizedError {
        case writerInitFailed(String)
        case startWritingFailed(String)

        var errorDescription: String? {
            switch self {
            case .writerInitFailed(let detail):
                return "Failed to create video writer: \(detail)"
            case .startWritingFailed(let detail):
                return "Failed to start writer session: \(detail)"
            }
        }
    }

    let outputURL: URL

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?

    private let lock = NSLock()
    private var sessionStarted = false
    private var isPaused = false
    private var isFinished = false

    init(outputURL: URL, width: Int, height: Int, captureAudio: Bool) throws {
        self.outputURL = outputURL
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw PipelineError.writerInitFailed(error.localizedDescription)
        }
        self.writer = writer

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        self.videoInput = videoInput

        if captureAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            if writer.canAdd(audioInput) {
                writer.add(audioInput)
            }
            self.audioInput = audioInput
        } else {
            self.audioInput = nil
        }
    }

    func startWriting() throws {
        lock.lock()
        defer { lock.unlock() }
        guard writer.startWriting() else {
            throw PipelineError.startWritingFailed(writer.error?.localizedDescription ?? "unknown")
        }
    }

    func setPaused(_ paused: Bool) {
        lock.lock()
        isPaused = paused
        lock.unlock()
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished, !isPaused else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !sessionStarted {
            writer.startSession(atSourceTime: pts)
            sessionStarted = true
        }
        if videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished, !isPaused, sessionStarted, let input = audioInput else { return }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    func finish() async {
        lock.lock()
        if isFinished {
            lock.unlock()
            return
        }
        isFinished = true
        let writerRef = writer
        let videoRef = videoInput
        let audioRef = audioInput
        let didStart = sessionStarted
        lock.unlock()

        videoRef.markAsFinished()
        audioRef?.markAsFinished()
        if didStart {
            await writerRef.finishWriting()
        } else {
            writerRef.cancelWriting()
        }
    }
}
